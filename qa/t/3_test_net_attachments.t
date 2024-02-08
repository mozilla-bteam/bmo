# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

# We have to upload files from the local computer. This requires
# chrome privileges.
my ($sel, $config) = get_selenium(CHROME_MODE);

log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Attachments'    => {
      'attachment_storage' => {type => 'select', value => 's3'},
      'attachment_s3_minsize' => {type => 'text', value => '5'},
    }
  }
);

### AWS S3

# First create a new bug with an attachment.
file_bug_in_product($sel, "TestProduct");
$sel->type_ok("short_desc", "Attachment stored in S3");
$sel->click_ok('attach-new-file');
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]', "new S3 attachment, v1");
$sel->check_ok('//input[@name="ispatch"]');
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("new S3 attachment, v1");

# Now attach another attachment to the existing bug.
$sel->click_ok('attachments-add-link');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]', "another S3 attachment, v2");
$sel->check_ok('//input[@name="ispatch"]');

# The existing attachment name must be displayed, to mark it as obsolete.
$sel->is_text_present_ok("new S3 attachment, v1");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');

# We need to store the attachment ID.
my $alink = $sel->get_attribute('//a[@title="another S3 attachment, v2"]@href');
$alink =~ /id=(\d+)/;
my $attachment1_id = $1;

# Be sure to redisplay the same bug, and make sure the new attachment is visible.
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok('another S3 attachment, v2');
logout($sel);

# Admins can delete attachments.
log_in($sel, $config, 'admin');
go_to_bug($sel, $bug1_id);
$sel->click_ok('//a[contains(@href,"/attachment.cgi?id='
    . $attachment1_id
    . '&action=edit")]');
# Wait a sec before the attachment overlay is loaded
sleep(1);
$sel->is_element_present_ok(
  qq{//h2[normalize-space(text())="Attachment $attachment1_id: [patch] another S3 attachment, v2"]}
);
$sel->click_ok('//dialog[@id="att-overlay"]//button[@data-action="delete"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Attachment $attachment1_id of Bug $bug1_id");
$sel->is_text_present_ok("Do you really want to delete this attachment?");
$sel->type_ok("reason", "deleted by Selenium");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok(
  "Changes to attachment $attachment1_id of bug $bug1_id submitted");
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("deleted by Selenium");
$sel->click_ok("link=attachment $attachment1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Attachment Removed");
$sel->is_text_present_ok(
  "The attachment you are attempting to access has been removed");

### Google Cloud Storage
set_parameters(
  $sel,
  {
    'Attachments'    => {
      'attachment_storage' => {type => 'select', value => 'google'},
      'attachment_google_minsize' => {type => 'text', value => '5'},
    }
  }
);

# First create a new bug with an attachment.
file_bug_in_product($sel, "TestProduct");
$sel->type_ok("short_desc", "Attachment stored in Google Cloud Storage");
$sel->click_ok('attach-new-file');
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]', "new gcs attachment, v1");
$sel->check_ok('//input[@name="ispatch"]');
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug2_id);
$sel->is_text_present_ok("new gcs attachment, v1");

# Now attach another attachment to the existing bug.
$sel->click_ok('attachments-add-link');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug2_id");
$sel->attach_file('//input[@name="data"]', $config->{attachment_file});
$sel->type_ok('//input[@name="description"]', "another gcs attachment, v2");
$sel->check_ok('//input[@name="ispatch"]');

# The existing attachment name must be displayed, to mark it as obsolete.
$sel->is_text_present_ok("new gcs attachment, v1");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('regexp:Attachment #\d+ to bug \d+ created');

# We need to store the attachment ID.
$alink = $sel->get_attribute('//a[@title="another gcs attachment, v2"]@href');
$alink =~ /id=(\d+)/;
my $attachment2_id = $1;

# Be sure to redisplay the same bug, and make sure the new attachment is visible.
go_to_bug($sel, $bug2_id);
$sel->is_text_present_ok('another gcs attachment, v2');
logout($sel);

# Admins can delete attachments.
log_in($sel, $config, 'admin');
go_to_bug($sel, $bug2_id);
$sel->click_ok('//a[contains(@href,"/attachment.cgi?id='
    . $attachment2_id
    . '&action=edit")]');
# Wait a sec before the attachment overlay is loaded
sleep(1);
$sel->is_element_present_ok(
  qq{//h2[normalize-space(text())="Attachment $attachment2_id: [patch] another gcs attachment, v2"]}
);
$sel->click_ok('//dialog[@id="att-overlay"]//button[@data-action="delete"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Attachment $attachment2_id of Bug $bug2_id");
$sel->is_text_present_ok("Do you really want to delete this attachment?");
$sel->type_ok("reason", "deleted by Selenium");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok(
  "Changes to attachment $attachment2_id of bug $bug2_id submitted");
go_to_bug($sel, $bug2_id);
$sel->is_text_present_ok("deleted by Selenium");
$sel->click_ok("link=attachment $attachment2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Attachment Removed");
$sel->is_text_present_ok(
  "The attachment you are attempting to access has been removed");

### Set back to database (default)

set_parameters(
  $sel,
  {
    'Attachments'    => {
      'attachment_storage' => {type => 'select', value => 'database'},
    }
  }
);

logout($sel);
