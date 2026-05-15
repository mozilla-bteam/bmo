#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Tests that attachments whose data is a recognized URL (GitHub PR, Google
# Doc, Phabricator revision) cause attachment.cgi to issue an HTTP redirect
# to that URL rather than serving the raw text.  Regression guard for the
# security fix that added the can_user_set / phabricator URL-detection changes.
use strict;
use warnings;
use 5.10.1;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::User;
use QA::Util qw(get_config);
use Bugzilla::Extension::PhabBugz::Constants qw(PHAB_CONTENT_TYPE);

use MIME::Base64 qw(encode_base64);
use Test::Mojo;
use Test::More;

my $config        = get_config();
my $admin_api_key = $config->{admin_user_api_key};
my $url           = Bugzilla->localconfig->urlbase;

# Do not follow redirects so we can assert the 302 and Location header
# directly rather than chasing the remote URL.
my $t = Test::Mojo->new();
$t->ua->max_redirects(0);

##########################################################################
# Section 1: Create a bug to host the test attachments
##########################################################################

my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test bug for attachment URL redirect',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'normal',
  description => 'This bug exists to test URL-attachment redirect behaviour.',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json =>
    $new_bug)->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};
ok($bug_id, "Created test bug $bug_id");

##########################################################################
# Helper: create an attachment via REST and return its id
##########################################################################

sub create_url_attachment {
  my ($raw_url, $label) = @_;

  my $att = {
    summary      => "URL attachment: $label",
    content_type => 'text/plain',
    data         => encode_base64($raw_url),
    file_name    => 'url-attachment.txt',
    is_patch     => 0,
    is_private   => 0,
  };

  $t->post_ok(
    $url . "rest/bug/$bug_id/attachment" =>
      {'X-Bugzilla-API-Key' => $admin_api_key} => json => $att)
    ->status_is(201);

  my ($id) = keys %{$t->tx->res->json->{attachments}};
  return $id;
}

##########################################################################
# Section 2: GitHub PR URL attachment → must redirect to GitHub
##########################################################################

my $github_url    = 'https://github.com/mozilla/firefox/pull/1234';
my $github_att_id = create_url_attachment($github_url, 'GitHub PR');

ok($github_att_id, "GitHub PR attachment created (id $github_att_id)");

$t->get_ok("${url}attachment.cgi?id=${github_att_id}" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(302, 'GitHub PR attachment.cgi returns 302')
  ->header_is('Location', $github_url,
  'GitHub PR redirect Location is the PR URL');

# Explicit content_type param must suppress the redirect (raw serve path)
$t->get_ok(
  "${url}attachment.cgi?id=${github_att_id}&content_type=text/plain" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200, 'Explicit content_type param suppresses redirect');

##########################################################################
# Section 3: Google Docs URL attachment → must redirect to Google Docs
##########################################################################

my $gdoc_url    = 'https://docs.google.com/document/d/abc123def456/edit';
my $gdoc_att_id = create_url_attachment($gdoc_url, 'Google Doc');

ok($gdoc_att_id, "Google Doc attachment created (id $gdoc_att_id)");

$t->get_ok("${url}attachment.cgi?id=${gdoc_att_id}" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(302, 'Google Doc attachment.cgi returns 302')
  ->header_is('Location', $gdoc_url,
  'Google Doc redirect Location is the doc URL');

$t->get_ok(
  "${url}attachment.cgi?id=${gdoc_att_id}&content_type=text/plain" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200, 'Explicit content_type param suppresses redirect');

##########################################################################
# Section 4: Phabricator URL attachment → must redirect to Phabricator
#
# Users cannot create text/x-phabricator-request attachments via the REST
# API (blocked by PhabBugz::Extension::object_before_create).  Mirror the
# production code path from PhabBugz::Util which sets
# allow_phab_revision_attachment in the request cache.
##########################################################################

SKIP: {
  my $phab_enabled  = Bugzilla->params->{phabricator_enabled};
  my $phab_base_uri = Bugzilla->params->{phabricator_base_uri};

  skip 'phabricator_enabled or phabricator_base_uri not set', 2
    unless $phab_enabled && $phab_base_uri;

  (my $phab_base = $phab_base_uri) =~ s{/?$}{/};
  my $phab_url = "${phab_base}D9999";

  my $admin_user = Bugzilla::User->check($config->{admin_user_login});
  Bugzilla->set_user($admin_user);

  my $bug           = Bugzilla::Bug->new($bug_id);
  my $request_cache = Bugzilla->request_cache;

  local $request_cache->{allow_phab_revision_attachment} = 1;

  my $phab_att = Bugzilla::Attachment->create({
    bug         => $bug,
    data        => $phab_url,
    description => 'Phabricator revision D9999',
    filename    => 'phabricator-D9999-url.txt',
    ispatch     => 0,
    isprivate   => 0,
    mimetype    => PHAB_CONTENT_TYPE,
  });

  ok($phab_att->id,
    "Phabricator attachment created directly (id " . $phab_att->id . ")");

  $t->get_ok("${url}attachment.cgi?id=" . $phab_att->id =>
      {'X-Bugzilla-API-Key' => $admin_api_key})
    ->status_is(302, 'Phabricator attachment.cgi returns 302')
    ->header_is('Location', $phab_url,
    'Phabricator redirect Location is the revision URL');
}

done_testing();
