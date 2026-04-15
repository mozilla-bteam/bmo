# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More 'no_plan';

use QA::Util;

# We have to upload files from the local computer. This requires
# chrome privileges.
my ($sel, $config) = get_selenium();

my $phab_content_type = 'text/x-phabricator-request';

# Log in as admin and create a bug with a normal attachment.
# We need an existing attachment to test the edit/update path.

log_in($sel, $config, 'admin');
file_bug_in_product($sel, 'Firefox');
$sel->select_ok('component', 'label=Installer');
$sel->type_ok('short_desc',
  'Test bug for Phabricator attachment content-type restriction');
$sel->type_ok('comment',
  'Testing that non-bot users cannot set Phabricator content type.');
$sel->click_ok('attach-new-file');
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]',
  'normal attachment for phabbugz test');
$sel->check_ok('//input[@name="ispatch"]');
$sel->click_ok('commit');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
$sel->is_text_present_ok('normal attachment for phabbugz test');

# Get the attachment ID from the link on the bug page
my $alink = $sel->find_element('//a[contains(text(), "normal attachment for phabbugz test")]')->get_attribute('href');
my ($attach_id) = $alink =~ /id=(\d+)/;
ok($attach_id, "Got attachment id: $attach_id");

### Test 1: Attempt to create an attachment with the Phabricator content type.
# This should fail with an "Invalid Content-Type" error page.

$sel->click_ok('attachments-add-link');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug_id");
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]', 'phab content type attachment');
$sel->click_ok('//input[@name="contenttypemethod" and @value="manual"]');
$sel->type_ok('//input[@name="contenttypeentry"]', $phab_content_type);
$sel->click_ok('create');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Invalid Content-Type',
  'Creating attachment with Phabricator content type is rejected');

# Go back to the bug to continue testing.
go_to_bug($sel, $bug_id);

### Test 2: Attempt to update an attachment's content type to the Phabricator type.
# The update should appear to succeed (no error page), but the hook silently
# reverts the content type back to the original value.

$sel->click_ok(
  '//a[contains(@href,"/attachment.cgi?id=' . $attach_id . '&action=edit")]');

# Wait for the attachment overlay to load.
sleep 1;
$sel->is_element_present_ok(
  qq{//h2[normalize-space(text())="Attachment $attach_id: [patch] normal attachment for phabbugz test"]}
);

# Clear the current content type and enter the Phabricator content type.
$sel->click_ok('//input[@name="contenttypemethod" and @value="manual"]');
$sel->type_ok('//dialog[@id="att-overlay"]//input[@name="contenttypeentry"]',
  $phab_content_type);
$sel->click_ok('//dialog[@id="att-overlay"]//input[@type="submit"]');

# Wait for the overlay to submit.
sleep 1;
$sel->wait_for_page_to_load_ok(WAIT_TIME);

# The page should reload back to the bug (no error).
$sel->is_text_present_ok('normal attachment for phabbugz test',
  'No error after attempting to set Phabricator content type on update');

### Test 3: Verify the content type was NOT changed (hook reverted it).

$sel->click_ok(
  '//a[contains(@href,"/attachment.cgi?id=' . $attach_id . '&action=edit")]');

# Wait for the attachment overlay to load.
sleep 1;
$sel->is_element_present_ok(
  qq{//h2[normalize-space(text())="Attachment $attach_id: [patch] normal attachment for phabbugz test"]}
);

my $current_content_type = $sel->get_value(
  '//dialog[@id="att-overlay"]//input[@name="contenttypeentry"]');
is($current_content_type, 'text/plain',
  'Content type was silently reverted to text/plain by the hook');

logout($sel);
