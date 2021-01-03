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

BEGIN {
  plan skip_all => "these tests only run in CI"
    unless $ENV{CI} && $ENV{CIRCLE_JOB} eq 'test_bmo';
}

my ($sel, $config) = get_selenium();

$sel->set_implicit_wait_timeout(600);

### Non-Mozilla normal user tests

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
$sel->title_is('Bugzilla Main Page', 'User is logged into Bugzilla');
$sel->logout_ok();

# Trying to login using normal username and password should redirect automatically
$sel->login($ENV{BZ_TEST_OAUTH2_NORMAL_USER}, $ENV{BZ_TEST_OAUTH2_PASSWORD});
$sel->click_ok('//a[contains(text(),"Connect")]',
  'Click OAuth2 provider login');
$sel->title_is('Bugzilla Main Page', 'User is logged into Bugzilla');
$sel->logout_ok();

### Mozilla user tests

# Logging in with Mozilla.com account should automatically redirect to OAuth2 login
$sel->login($ENV{BZ_TEST_OAUTH2_MOZILLA_USER}, $ENV{BZ_TEST_OAUTH2_PASSWORD});
$sel->click_ok('//a[contains(text(),"Connect")]',
  'Click OAuth2 provider login');
$sel->title_is('Bugzilla Main Page', 'User is logged into Bugzilla');
$sel->logout_ok();

done_testing;
