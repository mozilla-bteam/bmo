# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib);

use Test::More 'no_plan';

use Bugzilla::QA::Util;

my ($sel, $config) = get_selenium();

# Create new bug that you want to set a reminder for
log_in($sel, $config, 'editbugs');
file_bug_in_product($sel, 'TestProduct');
$sel->selected_label_is('component', 'TestComponent');
$sel->type_ok('short_desc', 'Test bug for reminders', 'Enter bug summary');
$sel->type_ok(
  'comment',
  'Created test bug for reminders',
  'Enter bug description'
);
$sel->click_ok('commit', undef, 'Commit bug data');
$sel->wait_for_page_to_load(WAIT_TIME);
my $bug1_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");
$sel->is_text_present_ok('has been added to the database',
  "Bug $bug1_id created");

# Click the Add Reminder button
$sel->click_ok('reminder-btn', 'Add Reminder');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');
$sel->type_ok('note',        'Remind me about this bug');
$sel->type_ok('remind_days', '10');
$sel->click_ok('add_reminder', 'Add the new reminder');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');
$sel->is_text_present_ok('Remind me about this bug', 'Bug reminder created');

# Bug should now say Remove Reminder
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok('Remove Reminder', 'Remove reminder button visible');
$sel->click_ok('reminder-btn', 'Remove Reminder');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');

# Remove the reminder
$sel->check_ok('//input[@name="remove" and @value="1"]');
$sel->click_ok('save_changes');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');
ok(!$sel->is_text_present('Remind me about this bug', 'Bug reminder removed'));

# Add a new reminder with todays date
my $today = DateTime->now()->strftime('%Y-%m-%d');
go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok('Add Reminder', 'Add reminder button visible');
$sel->click_ok('reminder-btn', 'Add Reminder');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');
$sel->type_ok('note',        'Remind me about this bug');
$sel->type_ok('remind_date', $today);
$sel->click_ok('add_reminder', 'Add the new reminder');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences');
$sel->is_text_present_ok('Remind me about this bug', 'Bug reminder created');
$sel->is_text_present_ok($today,                     'Correct date displayed');

# Run the script that generates the email reminder which should also remove
# the reminder from the user preferences page.
my $rv = system '/app/scripts/reminders.pl';
ok($rv == 0, 'Reminders script exited without error');
ok($sel->search_mailer_testfile(qr{Bug $bug1_id - Test bug for reminders}),
  'Email reminder found');
$sel->open_ok('/userprefs.cgi?tab=reminders');
$sel->title_is('User Preferences');
ok(!$sel->is_text_present('Remind me about this bug', 'Bug reminder removed'));
logout($sel);

done_testing();
