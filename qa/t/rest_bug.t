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
use QA::Util qw(get_config);

use MIME::Base64 qw(encode_base64 decode_base64);
use Test::Mojo;
use Test::More;

my $config  = get_config();
my $api_key = $config->{admin_user_api_key};
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Create new bug

my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'This is a new test bug',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
};

# First try unauthenticated. Should fail with error.
$t->post_ok($url . 'rest/bug' => json => $new_bug)->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Now try as authenticated user using API key. Should create a new bug.
$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# Retrieve the new bug and verify
$t->get_ok($url . "rest/bug/$bug_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is('/bugs/0/summary' => $new_bug->{summary});

### Section 2: Make updates to the bug

my $update = {
  type        => 'enhancement',
  severity    => 'minor',
  status      => 'ASSIGNED',
  assigned_to => $config->{admin_user_login},
  comment     => {body => 'Updating bug report'},
};

# Unauthenticated update should fail
$t->put_ok($url . "rest/bug/$bug_id" => json => $update)->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Authenticated request should work fine
$t->put_ok($url
    . "rest/bug/$bug_id" => {'X-Bugzilla-API-Key' => $api_key} => json => $update)
  ->status_is(200)->json_is('/bugs/0/id' => $bug_id)
  ->json_has('/bugs/0/changes');

# Retrieve the new bug and verify
$t->get_ok($url . "rest/bug/$bug_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is('/bugs/0/type' => $update->{type})
  ->json_is('/bugs/0/severity' => $update->{severity})
  ->json_is('/bugs/0/status'   => $update->{status});

### Section 3: Add a comment to the bug

$update = {comment => 'This is a new test comment',};

# Unauthenticated update should fail
$t->post_ok($url . "rest/bug/$bug_id/comment" => json => $update)
  ->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Authenticated request should work fine
$t->post_ok($url
    . "rest/bug/$bug_id/comment" => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $update)->status_is(201)->json_has('/id');

my $comment_id = $t->tx->res->json->{id};

# Retrieve the new comment and verify
$t->get_ok(
  $url . "rest/bug/comment/$comment_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/comments/$comment_id/text" => $update->{comment});

### Section 4: Attach a file to the bug

my $attach_data = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';

$update = {
  is_patch     => 1,
  comment      => 'This is a new attachment comment',
  summary      => 'Test Attachment',
  content_type => 'text/plain',
  data         => encode_base64($attach_data),
  file_name    => 'test_attachment.patch',
  obsoletes    => [],
  is_private   => 0,
};

# Unauthenticated update should fail
$t->post_ok($url . "rest/bug/$bug_id/attachment" => json => $update)
  ->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Authenticated request should work fine
$t->post_ok($url
    . "rest/bug/$bug_id/attachment" => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $update)->status_is(201)->json_has('/attachments');

my ($attach_id) = keys %{$t->tx->res->json->{attachments}};

# Retrieve the new attachment and verify
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is("/attachments/$attach_id/summary" => $update->{summary});

my $got_data = decode_base64($t->tx->res->json->{attachments}->{$attach_id}->{data});
ok($attach_data eq $got_data, 'Attachment data received is correct');

### Section 5: Finally close out the bug

$update = {status => 'RESOLVED', resolution => 'FIXED',};

$t->put_ok($url
    . "rest/bug/$bug_id" => {'X-Bugzilla-API-Key' => $api_key} => json => $update)
  ->status_is(200)->json_is('/bugs/0/id' => $bug_id)
  ->json_has('/bugs/0/changes');

done_testing();
