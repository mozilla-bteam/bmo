# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib);

use Bugzilla::QA::Util;
use Test::More;

my ($sel, $config) = get_selenium();

$sel->set_implicit_wait_timeout(600);

# Setup the parameters properly for Duo Security 2FA
log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'User Authentication' =>
      {'duo_uri' => {type => 'text', value => 'http://externalapi.test:8001'},}
  }
);

# Enable Duo for the admin user
$sel->open_ok('/userprefs.cgi?tab=mfa');
$sel->title_is('User Preferences');
$sel->click_ok('mfa-select-duo');
$sel->type_ok('mfa-duo-user', $config->{admin_user_login});
$sel->type_ok('mfa-password', $config->{admin_user_passwd});
$sel->click_ok('update');
$sel->click_ok('//a[contains(text(),"Redirect Back")]',
  'Click Duo Security verification');
$sel->title_is('User Preferences');
$sel->is_text_present_ok(
  'The changes to your two-factor authentication have been saved',
  'Duo successfully enabled');

# Disable Duo for the admin user
$sel->click_ok('mfa-disable');
$sel->type_ok('mfa-password', $config->{admin_user_passwd});
$sel->click_ok('update');
$sel->click_ok('//a[contains(text(),"Redirect Back")]',
  'Click Duo Security verification');
$sel->title_is('User Preferences');
$sel->is_text_present_ok(
  'The changes to your two-factor authentication have been saved',
  'Duo successfully disabled');

done_testing;
