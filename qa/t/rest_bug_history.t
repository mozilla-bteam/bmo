#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Test for REST call to Bug.history()               #
# GET /rest/bug/<id>/history                         #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use QA::Util qw(get_config);
use QA::Tests qw(STANDARD_BUG_TESTS);

use Test::Mojo;
use Test::More;

my $config = get_config();
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

foreach my $test (@{STANDARD_BUG_TESTS()}) {
  my $id = $test->{args}{ids}[0];

  # The "undef bug id" case is specific to the RPC param style and has no
  # single-resource REST URL equivalent, so it is skipped here.
  next if !defined $id;

  my %headers;
  if (my $user = $test->{user}) {
    my $api_key = $config->{"${user}_user_api_key"};
    $headers{'X-Bugzilla-API-Key'} = $api_key if $api_key;
  }

  my $path = $url . "rest/bug/$id/history";

  if (my $error = $test->{error}) {
    $t->get_ok($path => \%headers)->status_isnt(200);
    like($t->tx->res->json->{message}, qr/\Q$error\E/, "$test->{test}: $error");
  }
  else {
    $t->get_ok($path => \%headers)->status_is(200)->json_has('/bugs/0/id');
    is(scalar @{$t->tx->res->json->{bugs}}, 1, "$test->{test}: got exactly one bug");
    isa_ok($t->tx->res->json->{bugs}[0]{history}, 'ARRAY', "Bug's history");
  }
}

done_testing();
