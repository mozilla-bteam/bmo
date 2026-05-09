# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib);

use Test::More "no_plan";

use Bugzilla::QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');

# Add the milestone "100 Branch" with sortkey 100 to Firefox product

edit_product($sel, 'Firefox', 'Client Software');
$sel->click_ok('link=Edit milestones:', undef,
  'Go to the Edit milestones page');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select milestone of product 'Firefox'", 'Display milestones');
$sel->click_ok('link=Add', undef, 'Go add a new milestone');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Add Milestone to Product 'Firefox'", 'Enter new milestone');
$sel->type_ok('milestone', '100 Branch', 'Set its name to 100 Branch');
$sel->type_ok('sortkey',   '100',         'Set its sortkey to 100');
$sel->click_ok('create', undef, 'Submit data');
$sel->wait_for_page_to_load(WAIT_TIME);

# Add the version "Firefox 100" to Firefox product

edit_product($sel, 'Firefox', 'Client Software');
$sel->click_ok('link=Edit versions:', undef, 'Go to the Edit versions page');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select version of product 'Firefox'", 'Display versions');
$sel->click_ok('link=Add', undef, 'Go add a new version');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Add Version to Product 'Firefox'", 'Enter new version');
$sel->type_ok('version', 'Firefox 100', 'Set its name to Firefox 100');
$sel->click_ok('create', undef, 'Submit data');
$sel->wait_for_page_to_load(WAIT_TIME);

# Go to add new release admin page

go_to_admin($sel);
$sel->click_ok('link=New Firefox Release');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->select_ok('milestone_products', 'label=Firefox');
$sel->type_ok('new_milestone', '101');
$sel->type_ok('old_milestone', '100');
$sel->select_ok('version_products', 'label=Firefox');
$sel->type_ok('new_version', '101');
$sel->type_ok('old_version', '100');
$sel->click_ok('submit', undef, 'Submit data');
$sel->title_is('New Firefox Release');
$sel->is_text_present_ok('Milestone 101 Branch was added to product Firefox.');
$sel->is_text_present_ok('Milestone 100 Branch was disabled for product Firefox.');
$sel->is_text_present_ok('Version Firefox 101 was added to product Firefox.');
$sel->is_text_present_ok('Version Firefox 100 was disabled for product Firefox.');

# Verify that the new milestone and version has been create and the proper sortkey is present

edit_product($sel, 'Firefox', 'Client Software');
$sel->click_ok('link=Edit milestones:', undef,
  'Go to the Edit milestones page');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select milestone of product 'Firefox'", 'Display milestones');
$sel->is_text_present_ok('101 Branch', 'New milestone exists');
$sel->click_ok('link=101 Branch', undef, 'Go edit version');
$sel->title_is("Edit Milestone '101 Branch' of product 'Firefox'", 'Edit milestone');
$sel->value_is('sortkey', '110');

edit_product($sel, 'Firefox', 'Client Software');
$sel->click_ok('link=Edit versions:', undef, 'Go to the Edit versions page');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select version of product 'Firefox'", 'Display versions');
$sel->is_text_present_ok('Firefox 101', 'New version exists');

logout($sel);
