# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/lib", "$RealBin/../../lib", "$RealBin/../../local/lib/perl5";

use Test::More "no_plan";
use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters($sel, { "Bug Fields" => {"usetargetmilestone-on" => undef} });

# Create a new milestone to the 'TestProduct' product.

edit_product($sel, "TestProduct");
$sel->click_ok("link=Edit milestones:");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select milestone of product 'TestProduct'");
$sel->click_ok("link=Add");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Add Milestone to Product 'TestProduct'");
$sel->type_ok("milestone", "TM1");
$sel->type_ok("sortkey", "10");
$sel->click_ok("create");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Milestone Created");

# Edit the milestone of bugs.

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("component", "TestComponent");
my $bug_summary = "stone and rock";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment", "This bug is to test milestones");
my $bug1_id = create_bug($sel, $bug_summary);
$sel->is_text_present_ok("Target Milestone:");
$sel->select_ok("target_milestone", "label=TM1");
edit_bug($sel, $bug1_id, $bug_summary);

# Query for bugs with the TM1 milestone.

open_advanced_search_page($sel);
$sel->is_text_present_ok("Target Milestone:");
$sel->remove_all_selections_ok("product");
$sel->add_selection_ok("product", "label=TestProduct");
$sel->add_selection_ok("target_milestone", "label=TM1");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("One bug found");
$sel->type_ok("save_newqueryname", "selenium_m0");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
my $text = trim($sel->get_text("message"));
ok($text =~ /OK, you have a new search named selenium_m0./, "New search named selenium_m0 has been created");

# Turn off milestones and check that the milestone field no longer appears in bugs.

set_parameters($sel, { "Bug Fields" => {"usetargetmilestone-off" => undef} });

$sel->click_ok("link=Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search for bugs");
ok(!$sel->is_text_present("Target Milestone:"), "The target milestone field is no longer displayed in the search page");

go_to_bug($sel, $bug1_id);
ok(!$sel->is_text_present('//label[@for="target_milestone"]'), "The milestone field is no longer displayed in the bug page");

# The existing query must still work despite milestones are off now.

$sel->click_ok("link=selenium_m0");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: selenium_m0");
$sel->is_text_present_ok("One bug found");
$sel->click_ok("forget_search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, the selenium_m0 search is gone./, "The selenium_m0 search is gone");

# Re-enable the usetargetmilestone parameter and delete the created
# milestone from the Testproduct product.

set_parameters($sel, { "Bug Fields" => {"usetargetmilestone-on" => undef} });

edit_product($sel, "TestProduct");
$sel->click_ok("link=Edit milestones:");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Select milestone of product 'TestProduct'");
$sel->click_ok('//a[@href="editmilestones.cgi?action=del&product=TestProduct&milestone=TM1"]',
               undef, "Deleting the TM1 milestone");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Milestone of Product 'TestProduct'");
$text = trim($sel->get_body_text());
ok($text =~ /There is 1 bug entered for this milestone/, "Warning displayed about 1 bug targetted to TM1");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Milestone Deleted");
logout($sel);
