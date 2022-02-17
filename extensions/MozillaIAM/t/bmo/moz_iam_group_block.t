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

use Bugzilla;
use QA::Util qw(get_config);

use Test::Mojo;
use Test::More;

my $config  = get_config();
my $api_key = $config->{admin_user_api_key};
my $url     = Bugzilla->localconfig->urlbase;

my $bmo_email    = 'bmo-user-3@mozilla.com';
my $iam_username = 'mozilla-user-3@mozilla.com';
my $real_name    = 'Mozilla IAM User 3';

# We need to make the below changes as an empowered user
my $empowered_user
  = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

my $user = Bugzilla::User->create({
  login_name    => $bmo_email,
  realname      => $real_name,
  cryptpassword => '*',
  iam_username  => $iam_username,
});

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

# Trying to add mozilla-employee-confidential group should fail
my $changes = {groups => {add => ['mozilla-employee-confidential']}};
$t->put_ok($url
    . 'rest/user/'
    . $user->login => {'X-Bugzilla-API-Key' => $api_key} => json => $changes)
  ->status_is(400)->json_like('/message', qr/managed by Mozilla IAM/);

$user->set_iam_username('');
$user->update();

# Now that iam username is empty, the group change should work
$t->put_ok($url
    . 'rest/user/'
    . $user->login => {'X-Bugzilla-API-Key' => $api_key} => json => $changes)
  ->status_is(200)->json_has('/users/0/changes/groups');

done_testing();
