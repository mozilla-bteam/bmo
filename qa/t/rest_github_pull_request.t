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

use Digest::SHA  qw(hmac_sha256_hex);
use MIME::Base64 qw(decode_base64);
use Mojo::JSON   qw(encode_json true);
use QA::Util     qw(get_config);
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
  summary     => 'Test GitHub PR Linking',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# Not a pull request event
$t->post_ok($url . 'rest/github/pull_request' => {'X-GitHub-Event' => 'foobar'})
  ->status_is(400)
  ->json_like(
  '/message' => qr/The webhook event was not for a GitHub pull request/);

# Mismatching signatures
$t->post_ok($url
    . 'rest/github/pull_request'                                         =>
    {'X-Hub-Signature-256' => 'XXX', 'X-GitHub-Event' => 'pull_request'} =>
    json => {})->status_is(400)
  ->json_like('/message' =>
    qr/The webhook signature in the header did not match the expected value/);

# Invalid JSON
my $bad_payload = {
  pull_request => {
    html_url => 'https://github.com/mozilla-bteam/bmo/pull/1'
  }
};
my $bad_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($bad_payload), $github_secret);
$t->post_ok($url
    . 'rest/github/pull_request' => {'X-Hub-Signature-256' => $bad_signature,
    'X-GitHub-Event' => 'pull_request'} => json => $bad_payload)->status_is(400)
  ->json_like('/message' =>
    qr/The webhook did not contain valid JSON or expected data was missing/);

# Invalid Bug ID
$bad_payload = {
  pull_request => {
    html_url => 'https://github.com/mozilla-bteam/bmo/pull/1',
    title    => 'Bug 1000 - Test GitHub PR Linking',
    number   => 1,
  }
};
$bad_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($bad_payload), $github_secret);
$t->post_ok($url
    . 'rest/github/pull_request' => {'X-Hub-Signature-256' => $bad_signature,
    'X-GitHub-Event' => 'pull_request'} => json => $bad_payload)->status_is(400)
  ->json_like(
  '/message' => qr/The pull request title did not contain a valid bug ID/);

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/webhook-events-and-payloads
my $good_payload = {
  pull_request => {
    html_url => 'https://github.com/mozilla-bteam/bmo/pull/1',
    title    => "Bug $bug_id - Test GitHub PR Linking",
    number   => 1
  }
};

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/securing-your-webhooks
my $good_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);

# Post the valid GitHub event to the rest/github/pull_request API endpoint
$t->post_ok(
  $url
    . 'rest/github/pull_request' => {
    'X-Hub-Signature-256' => $good_signature,
    'X-GitHub-Event'      => 'pull_request'
    } => json => $good_payload
)->status_is(200)->json_has('/id');

my $attach_id = $t->tx->res->json->{id};

# Retrieve the new attachment from the bug to make sure it was created correctly
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/attachments/$attach_id/content_type",
  'text/x-github-pull-request')
  ->json_is("/attachments/$attach_id/description", 'GitHub Pull Request');

my $attach_data = $t->tx->res->json->{attachments}->{$attach_id}->{data};
$attach_data = decode_base64($attach_data);
ok($attach_data eq 'https://github.com/mozilla-bteam/bmo/pull/1');

# Bug already had the same github attachment so don't add twice
$t->post_ok(
  $url
    . 'rest/github/pull_request' => {
    'X-Hub-Signature-256' => $good_signature,
    'X-GitHub-Event'      => 'pull_request'
    } => json => $good_payload
)->status_is(400)
  ->json_like('/message' =>
    qr/The pull request contained a bug ID that already has an attachment/);

# Create a second bug for testing attaching the same github pr but to a
# different bug. For example if someone changes the bug ID in the title
# of an existing pull request. The first attachment should be obsoleted
# after creating the second one.
$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id_2 = $t->tx->res->json->{id};

# Post the valid GitHub event to the rest/github/pull_request API endpoint
$good_payload->{pull_request}->{title} = "Bug $bug_id_2 - Test GitHub PR Linking";
$good_signature = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);
$t->post_ok(
  $url
    . 'rest/github/pull_request' => {
    'X-Hub-Signature-256' => $good_signature,
    'X-GitHub-Event'      => 'pull_request'
    } => json => $good_payload
)->status_is(200)->json_has('/id');

my $attach_id_2 = $t->tx->res->json->{id};

# Retrieve the new attachment from the bug to make sure it was created correctly
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id_2" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/attachments/$attach_id_2/content_type",
  'text/x-github-pull-request')
  ->json_is("/attachments/$attach_id_2/description", 'GitHub Pull Request');

my $attach_data_2 = $t->tx->res->json->{attachments}->{$attach_id_2}->{data};
$attach_data_2 = decode_base64($attach_data_2);
ok($attach_data_2 eq 'https://github.com/mozilla-bteam/bmo/pull/1');

# Retrieve the old attachment from the previous bug and make sure it was obsoleted.
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/attachments/$attach_id/is_obsolete", true);

# Test that ping events (when the webhook is first created) are successful
# a valid signature is also provided
# Post the valid GitHub event to the rest/github/pull_request API endpoint
$good_payload = {hook => {type => 'Repository'}};
$good_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($good_payload), $github_secret);
$t->post_ok($url
    . 'rest/github/pull_request'                                           =>
    {'X-Hub-Signature-256' => $good_signature, 'X-GitHub-Event' => 'ping'} =>
    json => $good_payload)->status_is(200)->json_has('/success');

done_testing();
