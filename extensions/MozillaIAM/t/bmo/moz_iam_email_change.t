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
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla;
use Bugzilla::Logging;
use Bugzilla::Test::Selenium;
use Bugzilla::User;

use Test2::V0;

my $bmo_email     = 'bmo-user-2@mozilla.com';
my $iam_username  = 'mozilla-user-2@mozilla.com';
my $real_name     = 'Mozilla IAM User';
my $new_bmo_email = 'bmo-user-2-new@mozilla.com';

# We need to make the below changes as an empowered user
my $empowered_user
  = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

my $user = Bugzilla::User->create({
  login_name    => $bmo_email,
  realname      => $real_name,
  cryptpassword => '*',
  iam_username  => $iam_username,
});

$user->set_groups({add => ['mozilla-employee-confidential']});
$user->update();

ok(
  $user->iam_username eq $iam_username,
  "User iam_username is set to $iam_username"
);
ok(
  $user->in_group('mozilla-employee-confidential'),
  'User was added to the mozilla-employee-confidential group'
);

# Change users email address. Should automatically remove iam_username and
# mozilla group membership
$user->set_login($new_bmo_email);
$user->update();

undef $user;
$user = Bugzilla::User->new({name => $new_bmo_email});

ok(
  $user->iam_username ne $iam_username,
  "User iam_username is not $iam_username"
);
ok(!$user->in_group('mozilla-employee-confidential'),
  'User was removed from the mozilla-employee-confidential group');

# Check that password reset token was sent and clean up
my $token = Bugzilla::Test::Selenium->get_token();
ok($token, "got a token for resetting password");
Bugzilla->dbh->do('DELETE FROM tokens WHERE token = ?', undef, $token);
open my $fh, '>', '/app/data/mailer.testfile';
close $fh;

done_testing;
