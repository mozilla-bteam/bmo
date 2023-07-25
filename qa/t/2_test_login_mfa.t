# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Util qw(template_var);

use Auth::GoogleAuth;
use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

# Enable TOTP for the admin user
log_in($sel, $config, 'admin');
$sel->open_ok('/userprefs.cgi?tab=mfa');
$sel->title_is('User Preferences');
$sel->click_ok('mfa-select-totp');
$sel->type_ok('mfa-password', $config->{admin_user_passwd});

# Hack needed to click the show-text link in the TOTP iframe
# and then return the text based secret
my $secret32 = $sel->driver->execute_script('
  var iframe = document.getElementById("mfa-enable-totp-frame").contentWindow;
  var showText = iframe.document.getElementById("show-text");
  var oEvent = document.createEvent("MouseEvents");
  oEvent.initMouseEvent("click", true, true, window, 1, 1, 1, 1, 1, false, false, false, false, 0, showText);
  showText.dispatchEvent(oEvent);
  var secret = iframe.document.getElementById("secret");
  return secret.innerText;
');

ok($secret32, 'Correctly received secret32 from the form');

# Use the provided secret to generate the code needed to enable TOTP
my $auth = Auth::GoogleAuth->new({
  secret32 => $secret32,
  issuer   => template_var('terms')->{BugzillaTitle},
  key_id   => $config->{admin_user_login},
});

$sel->type_ok('mfa-totp-enable-code', $auth->code);
$sel->click_ok('update');
$sel->title_is('User Preferences');

logout($sel);

# Log back in but this time we are asked for a TOTP code
$sel->open_ok('/login', undef, 'Go to the home page');
$sel->title_is('Log in to Bugzilla');
$sel->type_ok(
  'Bugzilla_login',
  $config->{admin_user_login},
  'Enter admin login name'
);
$sel->type_ok(
  'Bugzilla_password',
  $config->{admin_user_passwd},
  'Enter admin password'
);
$sel->click_ok('log_in', undef, 'Submit credentials');
$sel->title_is('Account Verification');

# Enter an inccorrect TOTP code
$sel->type_ok('code', '123456');
$sel->click_ok('//input[@value="Submit"]');
my $error = $sel->get_text('verify_totp_error');
ok($error eq 'Invalid verification code.', 'Correct error generated for invalid code');

# Now enter the correct code
$sel->type_ok('code', $auth->code);
$sel->click_ok('//input[@value="Submit"]');
$sel->title_is('Bugzilla Main Page');

# Disable TOTP for the admin account
$sel->open_ok('/userprefs.cgi?tab=mfa');
$sel->title_is('User Preferences');
$sel->click_ok('mfa-disable');
$sel->type_ok('mfa-password', $config->{admin_user_passwd});
$sel->type_ok('code', $auth->code);
$sel->click_ok('update');
$sel->title_is('User Preferences');

logout($sel);

done_testing();
