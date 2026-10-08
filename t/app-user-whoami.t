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

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;
use Bugzilla::Test::Util qw(create_user issue_api_key);

use Bugzilla::Constants;
use Test2::V0;
use Test::Mojo;

# GET /rest/whoami is how a client validates an API key, so a key that is
# refused must say why (api_key_not_valid / api_key_revoked, internal code
# 306), as the legacy endpoint did, rather than the generic login_required
# (410) an anonymous request gets.

my $user = create_user('whoami@mozilla.org', '*');
my $key  = issue_api_key('whoami@mozilla.org');

my $t = Test::Mojo->new('Bugzilla::App');

$t->get_ok('/rest/whoami' => {'X-Bugzilla-API-Key' => $key->api_key})
  ->status_is(200)
  ->json_is('/id' => $user->id);

# No credentials at all.
$t->get_ok('/rest/whoami')->status_is(401)->json_is('/code' => 410);

# An unknown key, in the header or in the deprecated query parameters.
$t->get_ok('/rest/whoami' => {'X-Bugzilla-API-Key' => 'bogus-key-value'})
  ->status_isnt(200)
  ->json_is('/code' => 306)
  ->json_like('/message' => qr/API key you specified is invalid/);

foreach my $param (qw(api_key Bugzilla_api_key)) {
  $t->get_ok("/rest/whoami?$param=bogus-key-value")
    ->status_isnt(200)
    ->json_is('/code' => 306)
    ->json_like('/message' => qr/API key you specified is invalid/);
}

# A revoked key.
Bugzilla->set_user(Bugzilla::User->super_user);
$key->set_revoked(1);
$key->update();
Bugzilla->set_user(Bugzilla::User->new);

$t->get_ok('/rest/whoami' => {'X-Bugzilla-API-Key' => $key->api_key})
  ->status_isnt(200)
  ->json_is('/code' => 306)
  ->json_like('/message' => qr/has been revoked/);

done_testing;
