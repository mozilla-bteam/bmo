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

my ($sel, $config) = get_selenium();

$sel->set_implicit_wait_timeout(600);

# Clicking the OAuth2 login button and then creating a new account automatically
$sel->get_ok('/login', undef, 'Go to the home page');
$sel->title_is('Log in to Bugzilla', 'Log in to Bugzilla');
$sel->is_element_present_ok(
  '//div[@id="main-inner"]/div[@class="oauth2-login"]/a/button',
  'OAuth2 login button is present');
$sel->click_ok('//div[@id="main-inner"]/div[@class="oauth2-login"]/a/button',
  'Click OAuth2 login button');
$sel->click_ok('//a[contains(text(),"Connect")]',
  'Click OAuth2 provider login');
$sel->title_is('Verify Account Creation', 'Verify creation of new account');
$sel->click_ok('//input[@name="verify"]',
  'Click to verify creation of new account');
$sel->title_is('Bugzilla Main Page', 'User is logged into Bugzilla');
$sel->logout_ok();

# Next time clicking the OAuth2 login button should log the user in
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

# Make sure provider admin UI is only accessible by admin user
$sel->login($config->{admin_user_login}, $config->{admin_user_passwd});
$sel->get_ok('/admin/oauth/provider/list', undef, 'Go to the provider admin page');
$sel->title_is('Select OAuth2 Client', 'Select OAuth2 Client');
$sel->logout_ok();

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

done_testing;
