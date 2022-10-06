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
use Mojo::JSON   qw(encode_json);
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

# Create signature needed to be added to the GitHub header when
# posting the PR update.

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/webhook-events-and-payloads
my $payload = {
  pull_request => {
    html_url => 'https://github.com/mozilla-bteam/bmo/pull/1',
    title    => "Bug $bug_id - Test GitHub PR Linking",
  }
};

# https://docs.github.com/en/developers/webhooks-and-events/webhooks/securing-your-webhooks
my $github_signature
  = 'sha256=' . hmac_sha256_hex(encode_json($payload), $github_secret);

# Post the GitHub event to the rest/github/pull_request API endpoint

$t->post_ok(
  $url
    . 'rest/github/pull_request' => {
    'X-Hub-Signature-256' => $github_signature,
    'X-GitHub-Event'      => 'pull_request'
    } => json => $payload
)->status_is(200)->json_has('/id');

my $attach_id = $t->tx->res->json->{id};

# Retrieve the attachment from the bug to make sure it was created correctly

$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/attachments/$attach_id/content_type",
  'text/x-github-pull-request')
  ->json_is("/attachments/$attach_id/description", 'GitHub Pull Request');

my $attach_data = $t->tx->res->json->{attachments}->{$attach_id}->{data};
$attach_data = decode_base64($attach_data);
ok($attach_data eq 'https://github.com/mozilla-bteam/bmo/pull/1');

done_testing();
