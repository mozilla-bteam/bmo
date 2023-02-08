#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Logging;

use Digest::SHA qw(hmac_sha256_hex);
use Mojo::JSON  qw(encode_json true);
use QA::Util    qw(get_config);
use Mojo::Util  qw(dumper);
use Test::Mojo;
use Test::More;

my $config        = get_config();
my $api_key       = $config->{admin_user_api_key};
my $url           = Bugzilla->localconfig->urlbase;
my $github_secret = 'B1gS3cret!';

my $t = Test::Mojo->new();

# Create a new test bug for linking to PR
my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test GitHub Push Commenting',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# Not a push event
$t->post_ok($url . 'rest/github/push_comment' => {'X-GitHub-Event' => 'foobar'})
  ->status_is(400)
  ->json_like(
  '/message' => qr/The webhook event was not for a GitHub push commit/);

# Mismatching signatures
$t->post_ok($url
    . 'rest/github/push_comment'                                 =>
    {'X-Hub-Signature-256' => 'XXX', 'X-GitHub-Event' => 'push'} => json => {})
  ->status_is(400)
  ->json_like('/message' =>
    qr/The webhook signature in the header did not match the expected value/);

# Invalid JSON
my $bad_payload = {
  ref     => 'refs/heads/master',
  pusher  => {name => 'foobar'},
  commits => [{
    url => 'https://github.com/mozilla-bteam/bmo/commit/abcdefghijklmnopqrstuvwxyz',
  }]
};
my $bad_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($bad_payload), $github_secret);
$t->post_ok($url
    . 'rest/github/push_comment'                                          =>
    {'X-Hub-Signature-256' => $bad_signature, 'X-GitHub-Event' => 'push'} =>
    json => $bad_payload)->status_is(400)
  ->json_like('/message' =>
    qr/The webhook did not contain valid JSON or expected data was missing/);

# Missing bug IDs
$bad_payload = {
  ref     => 'refs/heads/master',
  pusher  => {name => 'foobar'},
  commits => [{
    url => 'https://github.com/mozilla-bteam/bmo/commit/abcdefghijklmnopqrstuvwxyz',
    message => 'Test Github Push Comment',
  }]
};
$bad_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($bad_payload), $github_secret);
$t->post_ok($url
    . 'rest/github/push_comment'                                          =>
    {'X-Hub-Signature-256' => $bad_signature, 'X-GitHub-Event' => 'push'} =>
    json => $bad_payload)->status_is(400)->json_is('/error', 1)
  ->json_like(
  '/message' => qr/The push commit message did not contain a valid bug ID/);

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/webhook-events-and-payloads
my $good_payload = {
  ref     => 'refs/heads/releases_v110',
  pusher  => {name => 'foobar'},
  commits => [{
    url => 'https://github.com/mozilla-bteam/bmo/commit/abcdefghijklmnopqrstuvwxyz',
    message => "Bug $bug_id - Test Github Push Comment",
  }]
};

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/securing-your-webhooks
my $good_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);

# Post the valid GitHub event to the rest/github/push_comment API endpoint
$t->post_ok($url
    . 'rest/github/push_comment'                                           =>
    {'X-Hub-Signature-256' => $good_signature, 'X-GitHub-Event' => 'push'} =>
    json => $good_payload)->status_is(200)->json_has("/bugs/$bug_id/id");

my $result     = $t->tx->res->json;
my $comment_id = $result->{bugs}->{$bug_id}->{id};

# Make sure comment text matches what is expected
my $comment_text
  = 'Authored by https://github.com/'
  . $good_payload->{pusher}->{name} . "\n"
  . $good_payload->{commits}->[0]->{url} . "\n"
  . $good_payload->{commits}->[0]->{message};

# Retrieve the new comment from the bug to make sure it was created correctly
$t->get_ok(
  $url . "rest/bug/comment/$comment_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)
  ->json_is("/comments/$comment_id/creator", 'automation@bmo.tld')
  ->json_is("/comments/$comment_id/text",    $comment_text);

# Bug should have been closed since it did not have the leave-open keyword
$t->get_ok($url
    . "rest/bug/$bug_id?include_fields=id,flags,status,resolution,_custom" =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200)
  ->json_is('/bugs/0/id', $bug_id)->json_is('/bugs/0/status', 'RESOLVED')
  ->json_is('/bugs/0/resolution',     'FIXED')
  ->json_is('/bugs/0/cf_status_firefox110', 'fixed')
  ->json_is('/bugs/0/flags/0/name',   'qe-verify')
  ->json_is('/bugs/0/flags/0/status', '+');

# Multiple commits with the same bug id should create a single comment
$good_payload = {
  ref     => 'refs/heads/master',
  pusher  => {name => 'foobar'},
  commits => [
    {
      url => 'https://github.com/mozilla-bteam/bmo/commit/abcdefghijklmnopqrstuvwxyz',
      message => "Bug $bug_id - First Test Github Push Comment",
    },
    {
      url => 'https://github.com/mozilla-bteam/bmo/commit/zyxwvutsrqponmlkjihgfedcba',
      message => "Bug $bug_id - Second Test Github Push Comment",
    }
  ]
};

$good_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);

$t->post_ok($url
    . 'rest/github/push_comment'                                           =>
    {'X-Hub-Signature-256' => $good_signature, 'X-GitHub-Event' => 'push'} =>
    json => $good_payload)->status_is(200)->json_has("/bugs/$bug_id/id");

$result     = $t->tx->res->json;
$comment_id = $result->{bugs}->{$bug_id}->{id};

# Make sure comment text matches what is expected
$comment_text
  = 'Authored by https://github.com/'
  . $good_payload->{pusher}->{name} . "\n"
  . $good_payload->{commits}->[0]->{url} . "\n"
  . $good_payload->{commits}->[0]->{message} . "\n\n"
  . 'Authored by https://github.com/'
  . $good_payload->{pusher}->{name} . "\n"
  . $good_payload->{commits}->[1]->{url} . "\n"
  . $good_payload->{commits}->[1]->{message};

# Retrieve the new comment from the bug to make sure it was created correctly
$t->get_ok(
  $url . "rest/bug/comment/$comment_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)
  ->json_is("/comments/$comment_id/creator", 'automation@bmo.tld')
  ->json_is("/comments/$comment_id/text",    $comment_text);

# Create a new bug that has the 'leave-open' keyword set to verify proper behavior
$new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test GitHub Push Commenting (leave-open)',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
  keywords    => ['leave-open'],
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id_2 = $t->tx->res->json->{id};

$good_payload = {
  ref     => 'refs/heads/master',
  pusher  => {name => 'foobar'},
  commits => [{
    url => 'https://github.com/mozilla-bteam/bmo/commit/abcdefghijklmnopqrstuvwxyz',
    message => "Bug $bug_id_2 - Test Github Push Comment (leave-open)",
  }]
};

$good_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);

# Post the valid GitHub event to the rest/github/push_comment API endpoint
$t->post_ok($url
    . 'rest/github/push_comment'                                           =>
    {'X-Hub-Signature-256' => $good_signature, 'X-GitHub-Event' => 'push'} =>
    json => $good_payload)->status_is(200)->json_has("/bugs/$bug_id_2/id");

$result     = $t->tx->res->json;
$comment_id = $result->{bugs}->{$bug_id_2}->{id};

# Make sure comment text matches what is expected
$comment_text
  = 'Authored by https://github.com/'
  . $good_payload->{pusher}->{name} . "\n"
  . $good_payload->{commits}->[0]->{url} . "\n"
  . $good_payload->{commits}->[0]->{message};

# Retrieve the new comment from the bug to make sure it was created correctly
$t->get_ok(
  $url . "rest/bug/comment/$comment_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)
  ->json_is("/comments/$comment_id/creator", 'automation@bmo.tld')
  ->json_is("/comments/$comment_id/text",    $comment_text);

# Bug should have stayed open since the leave-open keyword was set
$t->get_ok($url
    . "rest/bug/$bug_id_2?include_fields=id,flags,status,resolution" =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200)
  ->json_is('/bugs/0/id', $bug_id_2)->json_is('/bugs/0/status', 'CONFIRMED');

done_testing();
