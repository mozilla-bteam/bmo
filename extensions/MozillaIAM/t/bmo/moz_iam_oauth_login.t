#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;
use lib qw( . qa/t/lib local/lib/perl5 );

use Mojo::Base -strict;
use QA::Util;
use Test::More;

my $bmo_login    = $ENV{BZ_TEST_OAUTH2_NORMAL_USER};
my $iam_username = $ENV{BZ_TEST_OAUTH2_MOZILLA_USER};
my $password     = $ENV{BZ_TEST_OAUTH2_PASSWORD};

my ($sel, $config) = get_selenium();

$sel->set_implicit_wait_timeout(600);

# Logging in with Mozilla.com account should automatically redirect to OAuth2 login
$sel->login($iam_username, $password);
$sel->is_element_present_ok('//a[contains(text(),"Connect")]',
  'Mozilla IAM provider login present');
$sel->logout_ok();

# Click on Mozilla IAM login button
$sel->get_ok('/login', undef, 'Go to the home page');
$sel->title_is('Log in to Bugzilla', 'Log in to Bugzilla');
$sel->is_element_present_ok(
  '//div[@id="main-inner"]/div[@class="oauth2-login"]/a/button',
  'OAuth2 login button is present');
$sel->click_ok('//div[@id="main-inner"]/div[@class="oauth2-login"]/a/button',
  'Click OAuth2 login button');
$sel->click_ok('//a[contains(text(),"Connect")]',
  'Click OAuth2 provider login');
$sel->title_is('Bugzilla Main Page', 'User is logged into Bugzilla');
$sel->logout_ok();

# Make sure IAM username is correct and user is added to mozilla group
$sel->login($config->{admin_user_login}, $config->{admin_user_passwd});

# First we need to get the group id of the mozilla employee group.
$sel->get_ok('/editgroups.cgi', 'Go to edit groups');
$sel->title_is('Edit Groups', 'Edit groups loaded');
$sel->click_ok('link=mozilla-employee-confidential');
my $group_id
  = $sel->get_value("//input[\@name='group_id' and \@type='hidden']");

# Now check to make sure the user values are set properly
$sel->get_ok('/editusers.cgi', 'Go to edit users');
$sel->title_is('Search users', 'Edit users loaded');
$sel->type_ok('matchstr', $bmo_login, "Type $bmo_login for search");
$sel->click_ok('//input[@id="search"]');
$sel->title_is('Select user', 'Select a user loaded');
$sel->click_link($bmo_login);
$sel->title_like(qr/^Edit user/, "Edit user");
my $actual_iam_username = $sel->get_value('//input[@id="iam_username"]');
ok($actual_iam_username eq $iam_username, 'IAM username correct');
ok($sel->is_checked("//input[\@type='checkbox' and \@id='group_$group_id']"),
  'Mozilla employee group is selected');

done_testing;
