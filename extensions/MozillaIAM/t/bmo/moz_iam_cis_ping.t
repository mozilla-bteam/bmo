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

use Bugzilla;

BEGIN {
  Bugzilla->extensions;
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Extension::MozillaIAM::Person;
use Bugzilla::Logging;
use Bugzilla::Test::Selenium;
use Bugzilla::Test::Util qw(create_user mock_useragent_tx);
use Bugzilla::User;

use Mojo::JSON qw(encode_json false true);
use Test::Mojo;
use Test2::Tools::Mock;
use Test2::V0;

my $bmo_email    = $ENV{BZ_TEST_OAUTH2_NORMAL_USER};
my $iam_username = $ENV{BZ_TEST_OAUTH2_MOZILLA_USER};

my $t = Test::Mojo->new('Bugzilla::App');

# Simulate ping from CIS system about a user change
$t->post_ok(
  '/rest/mozillaiam/user/update' => json => {
    id        => 'ad|Mozilla-LDAP|mozilla-user-1',
    operation => 'update',
    time      => 10000
  }
)->status_is(200)->content_is('OK!');

# Process the new change from CIS
Bugzilla::Extension::MozillaIAM::Person->cis_update_query();

my $user = Bugzilla::User->new({name => $bmo_email});

ok($user->login eq $bmo_email, "User $bmo_email was created");
ok(
  $user->iam_username eq $iam_username,
  "User iam_username is set to $iam_username"
);
ok(
  $user->in_group('mozilla-employee-confidential'),
  'User was added to the mozilla-employee-confidential group'
);

# Remove bmo linkage from their CIS account. This should remove
# them from Mozilla confidential
local $ENV{CI} = 0, $ENV{NO_VERIFY_TOKEN} = 1;
my $mocked_data = {
  first_name        => {value => 'Mozilla'},
  last_name         => {value => 'IAM User'},
  primary_email     => {value => $iam_username},
  staff_information => {staff => {value => false}},
};
my $user_agent = mock 'Mojo::UserAgent' => (
  override => [
    post =>
      sub { return mock_useragent_tx('{"access_token":"fake_access_token"}'); },
    get => sub { return mock_useragent_tx(encode_json($mocked_data)); }
  ]
);

# Simulate ping from CIS system about a user change
$t->post_ok(
  '/rest/mozillaiam/user/update' => json => {
    id        => 'ad|Mozilla-LDAP|mozilla-user-1',
    operation => 'update',
    time      => 20000
  }
)->status_is(200)->content_is('OK!');

# Process the new change from CIS
Bugzilla::Extension::MozillaIAM::Person->cis_update_query();

$user = Bugzilla::User->new({name => $bmo_email});

ok($user->iam_username ne $iam_username, 'User iam_username is unset');
ok(!$user->in_group('mozilla-employee-confidential'),
  'User was removed from the mozilla-employee-confidential group');

# Check that password reset token was sent and clean up
my $token = Bugzilla::Test::Selenium->get_token();
ok($token, "got a token for resetting password");
Bugzilla->dbh->do('DELETE FROM tokens WHERE token = ?', undef, $token);
open my $fh, '>', '/app/data/mailer.testfile';
close $fh;

done_testing;
