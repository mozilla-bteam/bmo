#!/usr/bin/perl
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

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;

use Test2::V0;
use Test::Mojo;

my $t = Test::Mojo->new('Bugzilla::Quantum');

$t->get_ok('/login')->status_is(200)
  ->element_exists('div.login-form input[name=Bugzilla_login_token]')
  ->text_is('html head title' => 'Log in to Bugzilla');

my $login_token
  = $t->tx->res->dom->at('div.login-form input[name=Bugzilla_login_token]')->val;
ok $login_token, "Get login token ($login_token)";

print $t->tx->res->dom->at('div.login-form');

done_testing;
