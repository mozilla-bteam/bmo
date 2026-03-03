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

use MIME::Base64 qw(encode_base64);
use Test::Mojo;
use Test::More;

my $config        = get_config();
my $admin_api_key = $config->{admin_user_api_key};
my $url           = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

my $phab_content_type = 'text/x-phabricator-request';

### Section 1: Create a new bug (prerequisite)

my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test bug for Phabricator attachment content-type restriction',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'normal',
  description => 'This bug is used to test the Phabricator content-type restriction.',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};
ok($bug_id, "Bug created with id $bug_id");

### Section 2: Create attachment with Phabricator content type (should fail)

my $attach_data = 'This is test attachment data';

my $phab_attachment = {
  summary      => 'Test Phabricator attachment',
  content_type => $phab_content_type,
  data         => encode_base64($attach_data),
  file_name    => 'test_phab_attachment.txt',
  is_patch     => 0,
  is_private   => 0,
};

# Attempt to create attachment with Phabricator content type should fail.
# The hook strips mimetype to undef, causing invalid_content_type error.
$t->post_ok(
  $url . "rest/bug/$bug_id/attachment" =>
    {'X-Bugzilla-API-Key' => $admin_api_key} => json => $phab_attachment)
  ->status_is(400)
  ->json_like('/message' => qr/content.type/i,
    'Error message mentions content type');

### Section 3: Create attachment with normal content type (should succeed)

my $normal_attachment = {
  summary      => 'Test normal attachment',
  content_type => 'text/plain',
  data         => encode_base64($attach_data),
  file_name    => 'test_normal_attachment.txt',
  is_patch     => 0,
  is_private   => 0,
};

$t->post_ok(
  $url . "rest/bug/$bug_id/attachment" =>
    {'X-Bugzilla-API-Key' => $admin_api_key} => json => $normal_attachment)
  ->status_is(201)->json_has('/attachments');

my ($attach_id) = keys %{$t->tx->res->json->{attachments}};
ok($attach_id, "Attachment created with id $attach_id");

# Verify the content type is text/plain
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200)
  ->json_is("/attachments/$attach_id/content_type" => 'text/plain');

### Section 4: Update attachment content type to Phabricator type (should be silently reverted)

my $update = {
  content_type => $phab_content_type,
};

# The update call itself succeeds (HTTP 200) but the hook silently reverts the content type
$t->put_ok(
  $url . "rest/bug/attachment/$attach_id" =>
    {'X-Bugzilla-API-Key' => $admin_api_key} => json => $update)
  ->status_is(200);

# Retrieve the attachment and verify the content type was NOT changed
$t->get_ok(
  $url . "rest/bug/attachment/$attach_id" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200)
  ->json_is("/attachments/$attach_id/content_type" => 'text/plain',
    'Content type was silently reverted by the hook');

done_testing();
