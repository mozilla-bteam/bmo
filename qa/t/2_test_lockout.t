# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is 'Incompatible With Secondary Licenses', as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib);

use Test::More 'no_plan';

use Bugzilla::QA::Util;

my ($sel, $config) = get_selenium();

my $login = $config->{permanent_user_login};

# Try to log in to Bugzilla using a valid account but wrong password.
for (my $i = 1; $i < 5; $i++) {
  $sel->login($login, 'foo-bar-baz');
  $sel->title_is('Invalid Username Or Password');
}

# The fifth try should lock the account
$sel->login($login, 'foo-bar-baz');
$sel->title_is('Account Locked');
$sel->is_text_present_ok('This account has been locked out');

my ($user_found)
  = $sel->search_mailer_testfile(
  qr{Subject: \[Bugzilla\] Account Lock-Out: ($login)});

ok($user_found eq $login, 'Email sent successfully');

done_testing();
