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

my ($sel, $config) = get_selenium();

# Make sure non-permitted user cannot see graveyard page
log_in($sel, $config, 'editbugs');
$sel->open_ok('/admin/component/graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Authorization Required');
logout($sel);

# Make sure admin user can access graveyard page
log_in($sel, $config, 'admin');
$sel->open_ok('/admin/component/graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Component Graveyard');

# Make sure that selecting a product that does not have
# a graveyard equivalent throws an error
$sel->select_ok('product',   'Firefox');
$sel->select_ok('component', 'General');
$sel->click_ok('confirm_move', 'Confirm the move');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok(
  'Graveyard product \'Firefox Graveyard\' was not found.');

# Add the graveyard product for Firefox
go_to_admin($sel);
$sel->click_ok('link=Products');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Select Classification');
$sel->click_ok('link=Graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Select product in classification \'Graveyard\'');
$sel->click_ok('link=to classification \'Graveyard\'');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add Product');
$sel->type_ok('product',     'Firefox Graveyard');
$sel->type_ok('description', 'Description for Firefox Graveyard');
$sel->select_ok('security_group_id', 'label=core-security');
$sel->click_ok('add-product', 'Add the product');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Product Created');

# Now trying to move a component to Firefox Graveyard should work.
$sel->open_ok('/admin/component/graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Component Graveyard');
$sel->select_ok('product',   'Firefox');
$sel->select_ok('component', 'General');
$sel->click_ok('confirm_move', 'Confirm the move');
$sel->is_text_present_ok(
  'The component \'General\' will be moved from source product \'Firefox\' '
  . 'to destination product \'Firefox Graveyard\'.');

# Test for open bugs
file_bug_in_product($sel, 'Firefox');
my $bug_summary = 'Test bug for Firefox Graveyard';
$sel->select_ok('component', 'value=General');
$sel->type_ok('short_desc', $bug_summary);
$sel->type_ok('comment',    $bug_summary);
my $bug_id = create_bug($sel, $bug_summary);

$sel->open_ok('/admin/component/graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Component Graveyard');
$sel->select_ok('product',   'Firefox');
$sel->select_ok('component', 'General');
$sel->click_ok('confirm_move', 'Confirm the move');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok(
  'There are 1 open bugs for source product \'Firefox\' and component \'General\'. '
  . 'These will need to be closed first.');

# Close the bug and try the move again which should be allowed
go_to_bug($sel, $bug_id);
$sel->select_ok('bug_status', 'label=RESOLVED');
$sel->select_ok('resolution', 'label=FIXED');
$sel->click_ok('bottom-save-btn', 'Save changes');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $bug_id");

$sel->open_ok('/admin/component/graveyard');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Component Graveyard');
$sel->select_ok('product',   'Firefox');
$sel->select_ok('component', 'General');
$sel->click_ok('confirm_move');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok(
  'The component \'General\' will be moved from source product \'Firefox\' '
  . 'to destination product \'Firefox Graveyard\'.');

# Finally move the component
$sel->click_ok('do_the_move', 'Do the move');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('Component \'General\' successfully moved from source '
  . 'product \'Firefox\' to destination product \'Firefox Graveyard\'.');

# Verify the component is no longer in the Firefox product
$sel->open_ok('/describecomponents.cgi?product=Firefox');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Components for Firefox');
ok(!$sel->is_text_present(
  'For bugs in Firefox which do not fit into other more specific Firefox components'), 
  'General component is not in Firefox');

logout($sel);
