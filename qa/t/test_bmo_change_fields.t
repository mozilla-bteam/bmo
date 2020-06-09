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

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');

set_parameters($sel, {'Rules' => {'change_field_rules_enabled-on' => undef}});
my $rules = join '', <DATA>;
set_parameters($sel,
  {'Rules' => {'change_field_rules' => {type => 'text', value => $rules}}});

# 1. Create cf_cab_review custom field
# 2. Add values ?, approved to the cf_cab_review field
# 3. Create a new infra group
# 4. Add privileged user to the infra group but not the unprivileged user
# 5. Make sure privileged user can change to approved but unprivileged cannot
# 6. Create custom field from $cf_setters and sample values
# 7. Alter privilged user permissions accordingly and retest as above.

# Create cf_cab_review
go_to_admin($sel);
$sel->click_ok('link=Custom Fields');

$sel->click_ok('link=Add a new custom field');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add a new Custom Field');
$sel->type_ok('name', 'cf_cab_review');
$sel->type_ok('desc', 'Change Request');
$sel->select_ok('type', 'label=Drop Down');
$sel->click_ok('create');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Created');

# Create cf_colo_site (from cf_setters in extensions/BMO/lib/Data.pm)
$sel->click_ok('link=Add a new custom field');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add a new Custom Field');
$sel->type_ok('name', 'cf_colo_site');
$sel->type_ok('desc', 'colo-trip');
$sel->select_ok('type', 'label=Drop Down');
$sel->click_ok('create');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Created');

# Create infra group
go_to_admin($sel);
$sel->click_ok('link=Groups');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Edit Groups');
$sel->click_ok('link=Add Group');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Add group');
$sel->type_ok('name', 'infra');
$sel->type_ok('desc', 'Infrastructure-related Bugs');
$sel->type_ok('owner', $config->{'admin_user_login'});
$sel->check_ok('isactive');
$sel->uncheck_ok('insertnew');
$sel->click_ok('create');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('New Group Created');
my $group_id = $sel->get_value('group_id');

# Add the privileged user to the new infra group
my $login    = $config->{permanent_user_login};
my $username = $config->{permanent_user_username};
go_to_admin($sel);
$sel->click_ok('link=Users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->type_ok('matchstr', $login);
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Select user');
$sel->click_ok("link=$login");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user $username <$login>");
$sel->check_ok("//input[\@name='group_$group_id']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User $login updated");
$sel->is_text_present_ok('The account has been added to the infra group');

# if ($field =~ /^cf/sm && !@{$priv_results} && $new_value ne '---') {
#   # Cannot use the standard %cf_setter mapping as we want anyone
#   # to be able to set ?, just not the other values.
#   if ($field eq 'cf_cab_review') {
#     if ( $new_value ne '1'
#       && $new_value ne '?'
#       && !$user->in_group('infra', $bug->product_id))
#     {
#       push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
#     }
#   }
#   # "other" custom field setters restrictions
#   elsif (exists $cf_setters->{$field}) {
#     my $in_group = 0;
#     foreach my $group (@{$cf_setters->{$field}}) {
#       if ($user->in_group($group, $bug->product_id)) {
#         $in_group = 1;
#         last;
#       }
#     }
#     if (!$in_group) {
#       push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
#     }
#   }
# }


# elsif ($field eq 'resolution' && $new_value eq 'FIXED') {
#   # You need at least canconfirm to mark a bug as FIXED
#   if (!$user->in_group('canconfirm', $bug->{'product_id'})) {
#     push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
#   }
# }


# elsif (($field eq 'bug_status' && $old_value eq 'VERIFIED')
#   || ($field eq 'dup_id' && $bug->status->name eq 'VERIFIED')
#   || ($field eq 'resolution' && $bug->status->name eq 'VERIFIED'))
# {
#   # You need at least editbugs to reopen a resolved/verified bug
#   if (!$user->in_group('editbugs', $bug->{'product_id'})) {
#     push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
#   }
# }


# elsif ($user->in_group('canconfirm', $bug->{'product_id'})) {
#   # Canconfirm is really "cantriage"; users with canconfirm can also mark
#   # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
#   if ( $field eq 'bug_status'
#     && is_open_state($old_value)
#     && !is_open_state($new_value))
#   {
#     push @{$priv_results}, PRIVILEGES_REQUIRED_NONE;
#   }
#   elsif (
#     $field eq 'resolution'
#     && ( $new_value eq 'DUPLICATE'
#       || $new_value eq 'WORKSFORME'
#       || $new_value eq 'INCOMPLETE'
#       || (!$old_value && $new_value eq '1'))
#     )
#   {
#     push @{$priv_results}, PRIVILEGES_REQUIRED_NONE;
#   }
#   elsif ($field eq 'dup_id') {
#     push @{$priv_results}, PRIVILEGES_REQUIRED_NONE;
#   }
# }


# elsif ($field eq 'bug_status') {
#   # Disallow reopening of bugs which have been resolved for > 1 year
#   if ( is_open_state($new_value)
#     && !is_open_state($old_value)
#     && $bug->resolution eq 'FIXED')
#   {
#     my $days_ago = DateTime->now(time_zone => Bugzilla->local_timezone);
#     $days_ago->subtract(days => 365);
#     my $last_closed = datetime_from($bug->last_closed_date);
#     if ($last_closed lt $days_ago) {
#       push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
#     }
#   }
# }

# Cleanup
set_parameters($sel, {'Rules' => {'change_field_rules_enabled-off' => undef}});

go_to_admin($sel);
$sel->click_ok('link=Custom Fields');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Fields');

# Delete cf_cab_review
$sel->click_ok("//a[contains(\@href,'/editfields.cgi?action=edit&name=cf_cab_review')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_cab_review' (Change Request)");
$sel->click_ok('obsolete');
$sel->click_ok('edit');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Updated');
$sel->click_ok("//a[contains(\@href,'/editfields.cgi?action=del&name=cf_cab_review')]");
$sel->click_ok('link=Delete field \'Change Request\'');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Deleted');

# Delete cf_colo_site
$sel->click_ok("//a[contains(\@href,'/editfields.cgi?action=edit&name=cf_colo_site')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit the Custom Field 'cf_colo_site' (colo-trip)");
$sel->click_ok('obsolete');
$sel->click_ok('edit');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Updated');
$sel->click_ok("//a[contains(\@href,'/editfields.cgi?action=del&name=cf_colo_site')]");
$sel->click_ok('link=Delete field \'colo-trip\'');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Custom Field Deleted');

# Delete infra group
go_to_admin($sel);
$sel->click_ok('link=Groups');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Edit Groups');
$sel->click_ok("//a[contains(\@href,'/editgroups.cgi?action=del&group=${group_id}')]");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Delete group');
$sel->is_text_present_ok('Do you really want to delete this group?');
$sel->check_ok('removeusers');
$sel->click_ok('delete');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Group Deleted');
$sel->is_text_present_ok('The group infra has been deleted.');

logout($sel);

our $cf_setters
  = {'cf_colo_site' => ['infra', 'build'], 'cf_rank' => ['rank-setters'],};

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
  # Prevent users not in infra group from updating cf_colo_site
  name = "rank"
  error = "You cannot update the rank field"
  action = ["cannot_create", "cannot_update"]
  [rule.change]
    field = "cf_rank"
  [rule.condition]
    not_user_group = "rank-setters"
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
    bug_status = "RESOLVED"
    not_user_group = "editbugs"
