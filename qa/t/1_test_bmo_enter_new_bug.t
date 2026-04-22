# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Comments:
# 1. Some of the forms have been commented as they have been removed since
#    this script was originally created. I left them in insteading of deleting
#    so they could be used for reference for adding new form tests.
# 2. The _check_* utility functions for creating objects should be moved to
#    generate_test_data.pl at some point.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters($sel, {"Bug Fields" => {"useclassification-off" => undef}});

# trademark

_check_product('Marketing');
_check_component('Marketing', 'Trademark Permissions');
_check_group('marketing-private');

$sel->open_ok("/enter_bug.cgi?product=Marketing&format=trademark");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Trademark Usage Requests",
  "Open custom bug entry form - trademark");
$sel->type_ok("short_desc", "Bug created by Selenium", "Enter bug summary");
$sel->type_ok(
  "comment",
  "--- Bug created by Selenium ---",
  "Enter bug description"
);
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# mozlist

_check_product('mozilla.org');
_check_version('mozilla.org', 'other');
_check_component('mozilla.org', 'Discussion Forums');
_check_group('infra');

$sel->open_ok("/enter_bug.cgi?product=mozilla.org&format=mozlist");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Mozilla Discussion Forum",
  "Open custom bug entry form - mozlist");
$sel->type_ok("listName", "test-list", "Enter name for mailing list");
$sel->type_ok(
  "listAdmin",
  $config->{'admin_user_login'},
  "Enter list administator"
);
$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
$sel->check_ok("name=groups", "value=infra", "Select private group");
$sel->type_ok(
  "comment",
  "--- Bug created by Selenium ---",
  "Enter bug description"
);
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');

set_parameters($sel, {"Bug Fields" => {"useclassification-on" => undef}});
logout($sel);

sub _check_product {
  my ($product, $version) = @_;

  go_to_admin($sel);
  $sel->click_ok("link=Products");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Select product");

  my $product_description = "$product Description";

  my $text = trim($sel->get_text("bugzilla-body"));
  if ($text =~ /$product_description/) {

    # Product exists already
    return 1;
  }

  $sel->click_ok("link=Add");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Add Product");
  $sel->type_ok("product",     $product);
  $sel->type_ok("description", $product_description);
  $sel->type_ok("version",     $version) if $version;
  $sel->select_ok("security_group_id",   "label=core-security");
  $sel->select_ok("default_op_sys_id",   "label=Unspecified");
  $sel->select_ok("default_platform_id", "label=Unspecified");
  $sel->click_ok('//input[@type="submit" and @value="Add"]');
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $text = trim($sel->get_text("message"));
  ok(
    $text
      =~ /You will need to add at least one component before anyone can enter bugs against this product/,
    "Display a reminder about missing components"
  );

  return 1;
}

sub _check_component {
  my ($product, $component) = @_;

  go_to_admin($sel);
  $sel->click_ok("link=components");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Edit components for which product?");

  $sel->click_ok(
    "//*[\@id='bugzilla-body']//a[normalize-space(text())='$product']");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Select component of product '$product'");

  my $component_description = "$component Description";

  my $text = trim($sel->get_text("bugzilla-body"));
  if ($text =~ /$component_description/) {

    # Component exists already
    return 1;
  }

  go_to_admin($sel);
  $sel->click_ok("link=components");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Edit components for which product?");
  $sel->click_ok(
    "//*[\@id='bugzilla-body']//a[normalize-space(text())='$product']");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Select component of product '$product'");
  $sel->click_ok("link=Add");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Add component to the $product product");
  $sel->type_ok("component",    $component);
  $sel->type_ok("description",  $component_description);
  $sel->type_ok("initialowner", $config->{'admin_user_login'});
  $sel->type_ok("team_name",    'Mozilla');
  $sel->click_ok('//input[@type="submit" and @value="Add"]');
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Component Created");
  $text = trim($sel->get_text("message"));
  ok($text eq "The component $component has been created.",
    "Component successfully created");

  return 1;
}

sub _check_group {
  my ($group) = @_;

  go_to_admin($sel);
  $sel->click_ok("link=Groups");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Edit Groups");

  my $group_description = "$group Description";

  my $text = trim($sel->get_text("bugzilla-body"));
  if ($text =~ /$group_description/) {

    # Group exists already
    return 1;
  }

  $sel->title_is("Edit Groups");
  $sel->click_ok("link=Add Group");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Add group");
  $sel->type_ok("name",  $group);
  $sel->type_ok("desc",  $group_description);
  $sel->type_ok("owner", $config->{'admin_user_login'});
  $sel->check_ok("isactive");
  $sel->check_ok("insertnew");
  $sel->click_ok("create");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("New Group Created");
  my $group_id = $sel->get_value("group_id");

  return 1;
}

sub _check_version {
  my ($product, $version) = @_;

  go_to_admin($sel);
  $sel->click_ok("link=versions");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Edit versions for which product?");
  $sel->click_ok(
    "//*[\@id='bugzilla-body']//a[normalize-space(text())='$product']");
  $sel->wait_for_page_to_load(WAIT_TIME);

  my $text = trim($sel->get_text("bugzilla-body"));
  if ($text =~ /$version/) {

    # Version exists already
    return 1;
  }

  $sel->click_ok("link=Add");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_like(qr/^Add Version to Product/);
  $sel->type_ok("version", $version);
  $sel->click_ok("create");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Version Created");

  return 1;
}

sub _check_user {
  my ($user) = @_;

  go_to_admin($sel);
  $sel->click_ok("link=Users");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Search users");
  $sel->type_ok("matchstr", $user);
  $sel->click_ok("search");
  $sel->wait_for_page_to_load(WAIT_TIME);

  my $text = trim($sel->get_text("bugzilla-body"));
  if ($text =~ /$user/) {

    # User exists already
    return 1;
  }

  $sel->click_ok("link=add a new user");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is('Add user');
  $sel->type_ok('login',    $user);
  $sel->type_ok('password', 'icohF1io2ohw');
  $sel->click_ok("add");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->is_text_present(
    'regexp:The user account .* has been created successfully');

  return 1;
}
