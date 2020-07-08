# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla::Constants;

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');

set_parameters(
  $sel,
  {
    'Rules'      => {'change_field_rules_enabled-on' => undef},
    'Bug Fields' => {'useclassification-off'         => undef}
  }
);

my $rules = join '', <DATA>;
set_parameters($sel,
  {'Rules' => {'change_field_rules' => {type => 'text', value => $rules}}});

# Create cf_cab_review
check_custom_field($sel, 'cf_cab_review', 'Change Request');
add_values_custom_field(
  $sel, 'cf_cab_review',
  'Change Request',
  ['?', 'approved']
);

# Create cf_colo_site (from cf_setters in extensions/BMO/lib/Data.pm)
check_custom_field($sel, 'cf_colo_site', 'colo-trip');
add_values_custom_field($sel, 'cf_colo_site', 'colo-trip', ['ams1', 'ber3']);

# Create infra group
check_group($sel, 'infra', 'Infrastructure-related Bugs');

# Add the privileged user to the new infra group
add_user_group(
  $sel, 'infra',
  $config->{permanent_user_login},
  $config->{permanent_user_username}
);

# Create rank-setters group
check_group($sel, 'rank-setters', 'Rank Setters');

# Add the privileged user to the new infra group
add_user_group(
  $sel, 'rank-setters',
  $config->{permanent_user_login},
  $config->{permanent_user_username}
);

# Create product and component needed for tests
check_product($sel, 'Infrastructure & Operations');
check_component($sel, 'Infrastructure & Operations', 'RelOps');

logout($sel);

# Make sure cf_vab_review::approved is not available for unprivileged user
# for both creating and editing bugs
log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'Infrastructure & Operations');
$sel->select_ok('component', 'label=RelOps');
$sel->type_ok(
  'short_desc',
  'Bug created by Unprivileged User',
  'Enter bug summary'
);
$sel->type_ok(
  'comment',
  '--- Bug created by Selenium ---',
  'Enter bug description'
);
$sel->click_ok('commit', undef, 'Submit bug data to post_bug.cgi');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
if ($sel->is_element_present('cab-review-gate-close')) {
  $sel->click_ok('cab-review-gate-close');
}
$sel->is_element_present_ok('//select[@id="cf_cab_review"]/option[@value="?"]',
  '? is present in select');
ok(
  !$sel->is_element_present(
    '//select[@id="cf_cab_review"]/option[@value="approved"]'),
  'approved is missing from select'
);
$sel->select_ok('cf_cab_review', 'label=?');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

log_in($sel, $config, 'permanent');
go_to_bug($sel, $bug_id);
if ($sel->is_element_present('cab-review-gate-close')) {
  $sel->click_ok('cab-review-gate-close');
}
$sel->is_element_present_ok('//select[@id="cf_cab_review"]/option[@value="?"]',
  '? is present in select');
$sel->is_element_present_ok(
  '//select[@id="cf_cab_review"]/option[@value="approved"]',
  'approved is present in select');
$sel->select_ok('cf_cab_review', 'label=approved');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

# Make sure cf_colo_site::ams1 is not available for unprivileged user for editing bugs
log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug_id);
ok(
  !$sel->is_element_present('//select[@id="cf_colo_site"]/option[@value="ams1"]'),
  'ams1 is missing from select'
);
logout($sel);

log_in($sel, $config, 'permanent');
go_to_bug($sel, $bug_id);
$sel->is_element_present_ok(
  '//select[@id="cf_colo_site"]/option[@value="ams1"]',
  'ams1 is present in select');
$sel->select_ok('cf_colo_site', 'label=ams1');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

# Make sure cf_rank is not settable by unprivileged user when editing bugs
log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'Firefox');
$sel->select_ok('component', 'label=General');
$sel->type_ok(
  'short_desc',
  'Bug created by Unprivileged User',
  'Enter bug summary'
);
$sel->type_ok(
  'comment',
  '--- Bug created by Selenium ---',
  'Enter bug description'
);
$sel->click_ok('commit', undef, 'Submit bug data to post_bug.cgi');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
ok(!$sel->is_editable('cf_rank'), 'Rank should not be editable');
logout($sel);

log_in($sel, $config, 'permanent');
go_to_bug($sel, $bug_id);
$sel->is_editable_ok('cf_rank', 'Rank is editable by user');
$sel->type_ok('cf_rank', '10');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

# Unprivileged user cannot resolve a bug as FIXED if not in canconfirm group
log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'TestProduct');
$sel->type_ok(
  'short_desc',
  'Bug created by Unprivileged User',
  'Enter bug summary'
);
$sel->type_ok(
  'comment',
  '--- Bug created by Selenium ---',
  'Enter bug description'
);
$sel->click_ok('commit', undef, 'Submit bug data to post_bug.cgi');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=RESOLVED');
ok(
  !$sel->is_element_present('//select[@id="resolution"]/option[@value="FIXED"]'),
  'FIXED is missing from select'
);
logout($sel);

log_in($sel, $config, 'permanent');
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=RESOLVED');
$sel->select_ok('resolution', 'label=FIXED');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

# User without editbugs cannot reopen a bug closed as VERIFIED
log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'TestProduct');
$sel->type_ok(
  'short_desc',
  'Bug created by Unprivileged User',
  'Enter bug summary'
);
$sel->type_ok(
  'comment',
  '--- Bug created by Selenium ---',
  'Enter bug description'
);
$sel->click_ok('commit', undef, 'Submit bug data to post_bug.cgi');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
logout($sel);

log_in($sel, $config, 'permanent');
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=RESOLVED');
$sel->select_ok('resolution', 'label=FIXED');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=VERIFIED');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug_id);
ok(
  !$sel->is_element_present(
    '//select[@id="bug_status"]/option[@value="REOPENED"]'),
  'User is unable to update a VERIFIED bug',
);
logout($sel);

# Prevent users who aren't in editbugs from setting priority
log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, "Firefox");
$sel->type_ok(
  "short_desc",
  "Bug created by Unprivileged User",
  "Enter bug summary"
);
$sel->type_ok(
  "comment",
  "--- Bug created by Selenium ---",
  "Enter bug description"
);
ok(!$sel->is_element_present('//select[@id="priority"]/option[@value="P1"]'),
  'Priority cannot be set');
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
ok(!$sel->is_element_present('//select[@id="priority"]/option[@value="P1"]'),
  'Priority cannot be set');
logout($sel);

log_in($sel, $config, 'permanent');
file_bug_in_product($sel, "Firefox");
$sel->type_ok(
  "short_desc",
  "Bug created by Permanent User",
  "Enter bug summary"
);
$sel->type_ok(
  "comment",
  "--- Bug created by Selenium ---",
  "Enter bug description"
);
$sel->is_element_present_ok('//select[@id="priority"]/option[@value="P1"]',
  'Priority can be set');
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
$sel->is_element_present_ok('//select[@id="priority"]/option[@value="P1"]',
  'Priority can be set');
logout($sel);

# People without editbugs can’t comment on closed bugs
log_in($sel, $config, 'permanent');
file_bug_in_product($sel, "Firefox");
$sel->type_ok(
  "short_desc",
  "Bug created by permanent User",
  "Enter bug summary"
);
$sel->type_ok(
  "comment",
  "--- Bug created by Selenium ---",
  "Enter bug description"
);
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
$bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=RESOLVED');
$sel->select_ok('resolution', 'label=FIXED');
$sel->click_ok('bottom-save-btn', 'Save changes');
check_page_load($sel, qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
$sel->is_text_present_ok("Changes submitted for bug $bug_id");
logout($sel);

log_in($sel, $config, 'unprivileged');
go_to_bug($sel, $bug_id);
ok(!$sel->is_element_present('comment'),
  'New comment cannot be added');
logout($sel);

# Cleanup
log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Rules'      => {'change_field_rules_enabled-off' => undef},
    'Bug Fields' => {'useclassification-on'           => undef}
  }
);
logout($sel);

__DATA__
# This will create an array of rules in TOML
[[rule]]
  # Prevent users not in infra group from updating cf_cab_review
  name = "cab review"
  error = "You cannot update the cab review field"
  action = ["cannot_create", "cannot_update"]
  [rule.change]
    field = "cf_cab_review"
    not_new_value = ["1","?"]
  [rule.condition]
    not_user_group = "infra"
[[rule]]
  # Prevent users not in infra group from updating cf_colo_site
  name = "colo site"
  error = "You cannot update the colo site field"
  action = ["cannot_create", "cannot_update"]
  [rule.change]
    field = "cf_colo_site"
  [rule.condition]
    not_user_group = ["infra", "build"]
[[rule]]
  # Prevent users not in rank-setters group from updating cf_rank
  name = "rank"
  error = "You cannot update the rank field"
  action = ["cannot_create", "cannot_update"]
  [rule.change]
    field = "cf_rank"
  [rule.condition]
    not_user_group = "rank-setters"
[[rule]]
  # User without editbugs cannot update a bug closed as VERIFIED
  name = "reopen verified"
  error = "You cannot update VERIFIED bug without editbugs."
  action = ["cannot_update"]
  [rule.change]
    field = "bug_status"
  [rule.condition]
    bug_status = "VERIFIED"
    not_user_group = "editbugs"
[[rule]]
  # User without editbugs cannot update bug closed as VERIFIED
  name = "duplicate verified"
  error = "You cannot update VERIFIED bug without editbugs."
  action = ["cannot_update"]
  [rule.change]
    field = "dup_id"
  [rule.condition]
    bug_status = "VERIFIED"
    not_user_group = "editbugs"
[[rule]]
  # User without editbugs cannot update a bug closed as VERIFIED
  name = "resolution verified"
  error = "You cannot reopen VERIFIED bug without editbugs."
  action = ["cannot_update"]
  [rule.change]
    field = "resolution"
  [rule.condition]
    bug_status = "VERIFIED"
    not_user_group = "editbugs"
[[rule]]
  # Prevent users who aren't in editbugs from setting priority
  name = "firefox priority"
  error = "You cannot set the priority of a bug."
  action = ["cannot_update","cannot_create"]
  [rule.filter]
    product = "Firefox"
  [rule.change]
    field = "priority"
  [rule.condition]
    not_user_group = "editbugs"
[[rule]]
  # Prevent users who aren't in editbugs from assigning Firefox bugs
  name = "firefox assignee"
  error = "You cannot assign this bug."
  action = ["cannot_update", "cannot_create"]
  [rule.filter]
    product = "Firefox"
  [rule.change]
    field = "assigned_to"
  [rule.condition]
    not_user_group = "editbugs"
[[rule]]
  # Require canconfirm to mark a bug as FIXED
  name = "fixed canconfirm"
  error = "You cannot mark this bug as FIXED"
  action = "cannot_update"
  [rule.change]
    field = "resolution"
    new_value = "FIXED"
  [rule.condition]
    not_user_group = "canconfirm"
[[rule]]
  # People without editbugs can’t comment on closed bugs
  name = "closed can comment"
  error = "You cannot comment on closed bugs"
  action = "cannot_comment"
  [rule.change]
    field = "longdesc"
  [rule.condition]
    bug_status = ["RESOLVED", "VERIFIED"]
    not_user_group = "editbugs"
