# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../.. ../../local/lib/perl5);

use Bugzilla;
use QA::Util;
use Test::Mojo;
use Test::More 'no_plan';

my ($sel, $config) = get_selenium();

# Add new config variables for the duo user
$config->{duo_user_login}     = 'duo@mozilla.test';
$config->{duo_bot_user_login} = 'duo-bot@mozilla.tld';
$config->{duo_user_passwd}    = 'uChoopoh1che';

# Create duo required group and excluded group
log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok('link=Groups');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Edit Groups');
$sel->click_ok('link=Add Group');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Add group');
$sel->type_ok('name',  'duo_required_group');
$sel->type_ok('desc',  'Duo Required Group');
$sel->type_ok('owner', $config->{'admin_user_login'});
$sel->check_ok('isactive');
$sel->uncheck_ok('insertnew');
$sel->click_ok('create');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('New Group Created');
my $required_group_id = $sel->get_value('group_id');

go_to_admin($sel);
$sel->click_ok('link=Groups');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Edit Groups');
$sel->click_ok('link=Add Group');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Add group');
$sel->type_ok('name',  'duo_required_excluded_group');
$sel->type_ok('desc',  'Duo Required Excluded Group');
$sel->type_ok('owner', $config->{'admin_user_login'});
$sel->check_ok('isactive');
$sel->uncheck_ok('insertnew');
$sel->click_ok('create');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('New Group Created');
my $excluded_group_id = $sel->get_value('group_id');

# Update the system parameters to enable the new groups for duo requirement
set_parameters(
  $sel,
  {
    'User Authentication' => {
      'duo_required_group' => {type => 'select', value => 'duo_required_group'},
      'duo_required_excluded_group' =>
        {type => 'select', value => 'duo_required_excluded_group'},
    }
  }
);

# Create new regular user that will be required to use duo mfa
go_to_admin($sel);
$sel->click_ok('link=Users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->click_ok('link=add a new user');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add user');
$sel->type_ok('login',    $config->{duo_user_login});
$sel->type_ok('name',     'duo-user');
$sel->type_ok('password', $config->{duo_user_passwd}, 'Enter password');
$sel->click_ok('add');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user duo-user <$config->{duo_user_login}>");
$sel->check_ok("//input[\@name='group_$required_group_id']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User $config->{duo_user_login} updated");

# Create new bot user that will be in the Duo required group but
# will be excluded from having to use Duo
go_to_admin($sel);
$sel->click_ok('link=Users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->click_ok('link=add a new user');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Add user');
$sel->type_ok('login',    $config->{duo_bot_user_login});
$sel->type_ok('name',     'duo-user');
$sel->type_ok('password', $config->{duo_user_passwd}, 'Enter password');
$sel->click_ok('add');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user duo-user <$config->{duo_bot_user_login}>");
$sel->check_ok("//input[\@name='group_$required_group_id']");
$sel->check_ok("//input[\@name='group_$excluded_group_id']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User $config->{duo_bot_user_login} updated");
logout($sel);

# Login as normal user and observe that user must enable duo mfa
$sel->open_ok('/login', undef, 'Go to the home page');
$sel->title_is('Log in to Bugzilla');
$sel->type_ok(
  'Bugzilla_login',
  $config->{duo_user_login},
  "Enter $config->{duo_user_login} login name"
);
$sel->type_ok(
  'Bugzilla_password',
  $config->{duo_user_passwd},
  "Enter $config->{duo_user_login} password"
);
$sel->click_ok('log_in', undef, 'Submit credentials');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences', 'MFA user preferences is displayed');
$sel->is_text_present_ok('You are a member of a group that requires Duo Security to be used for your MFA');

# Next, lets's remove user from duo groups using REST API
# which should trigger several changes to the user.
# 1. Log out the users current session
# 2. Clear the users password (set to '*')
# 3. Require the user set up new MFA (redirect to user preferences)

my $t = Test::Mojo->new;

# Set the user mfa to Duo
my $user_update = {mfa => 'Duo'};
$t->put_ok(Bugzilla->localconfig->urlbase
    . "rest/user/$config->{duo_user_login}"                 =>
    {'X-Bugzilla-API-Key' => $config->{admin_user_api_key}} => json =>
    $user_update)->status_is(200)->json_has('/users');

# Remove user from Duo requirement group
$user_update = {groups => {remove => ['duo_required_group']}};
$t->put_ok(Bugzilla->localconfig->urlbase
    . "rest/user/$config->{duo_user_login}"                 =>
    {'X-Bugzilla-API-Key' => $config->{admin_user_api_key}} => json =>
    $user_update)->status_is(200)->json_has('/users');

$sel->open_ok('/enter_bug.cgi', undef, 'Try to enter a new bug');
$sel->title_is('Log in to Bugzilla', 'User should be logged out');

# Using old password should not work as it should have been cleared
$sel->type_ok(
  'Bugzilla_login',
  $config->{duo_user_login},
  "Enter $config->{duo_user_login} login name"
);
$sel->type_ok(
  'Bugzilla_password',
  $config->{duo_user_passwd},
  "Enter $config->{duo_user_login} password"
);
$sel->click_ok('log_in', undef, 'Submit credentials');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Invalid Username Or Password',
  'Previous password should no longer work');

# Reset password using API
$user_update = {password => $config->{duo_user_passwd}};
$t->put_ok(Bugzilla->localconfig->urlbase
    . "rest/user/$config->{duo_user_login}"                 =>
    {'X-Bugzilla-API-Key' => $config->{admin_user_api_key}} => json =>
    $user_update)->status_is(200)->json_has('/users');

# User just removed from duo required must add MFA
# to their account once they have logged in
$sel->open_ok('/enter_bug.cgi', undef, 'Try to enter a new bug');
$sel->type_ok(
  'Bugzilla_login',
  $config->{duo_user_login},
  "Enter $config->{duo_user_login} login name"
);
$sel->type_ok(
  'Bugzilla_password',
  $config->{duo_user_passwd},
  "Enter $config->{duo_user_login} password"
);
$sel->click_ok('log_in', undef, 'Submit credentials');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('User Preferences', 'MFA user preferences is displayed');
logout($sel);

# Login as bot user and observe that user does not need to enable duo mfa
$sel->open_ok('/login', undef, 'Go to the home page');
$sel->title_is('Log in to Bugzilla');
$sel->type_ok(
  'Bugzilla_login',
  $config->{duo_bot_user_login},
  "Enter $config->{duo_bot_user_login} login name"
);
$sel->type_ok(
  'Bugzilla_password',
  $config->{duo_user_passwd},
  "Enter $config->{duo_bot_user_login} password"
);
$sel->click_ok('log_in', undef, 'Submit credentials');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Bugzilla Main Page', 'User is logged in');
logout($sel);

# Add the normal user to the duo excluded group and observe error
# that user is not a bot account
log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok('link=Users');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Search users');
$sel->type_ok('matchstr', $config->{duo_user_login});
$sel->select_ok('matchtype', 'label=exact (find this user)');
$sel->click_ok('search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit user duo-user <$config->{duo_user_login}>");
$sel->check_ok("//input[\@name='group_$excluded_group_id']");
$sel->click_ok('update');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Only Bot Accounts Excluded');
logout($sel);

# Turn off duo requirement
log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'User Authentication' => {
      'duo_required_group'          => {type => 'select', value => ''},
      'duo_required_excluded_group' => {type => 'select', value => ''},
    }
  }
);
logout($sel);

done_testing();
