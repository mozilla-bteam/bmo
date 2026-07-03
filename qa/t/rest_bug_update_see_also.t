#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Test for REST handling of see_also add/remove     #
# (formerly Bug.update_see_also; the REST API        #
#  exposes this through Bug.update's see_also field). #
# PUT /rest/bug/<id>                                  #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use QA::Util qw(get_config);
use QA::Tests qw(PRIVATE_BUG_USER STANDARD_BUG_TESTS);
use QA::REST::Util qw(api_headers);

use Test::Mojo;
use Test::More;

my $config = get_config();
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

my $bug_url = 'https://bugzilla-dev.allizom.org/show_bug.cgi?id=100';

# see_also updates don't support logged-out users.
my @tests = grep { $_->{user} } @{STANDARD_BUG_TESTS()};
foreach my $test (@tests) {
  $test->{args}->{add} = $test->{args}->{remove} = [];
}

push(
  @tests,
  (
    {user => 'unprivileged', args => {ids => ['public_bug'], add => [$bug_url]}, error => 'only the assignee or reporter of the bug, or a user', test => 'Unprivileged user cannot add a URL to a bug'},
    {user => 'admin', args => {ids => ['public_bug'], add => ['asdfasdfasdf']}, error => 'ASDF', test => 'Admin cannot add an invalid URL'},
    {user => 'admin', args => {ids => ['public_bug'], remove => ['asdfasdfasdf']}, test => 'Invalid URL silently ignored'},
    {user => 'admin', args => {ids => ['public_bug'], add => [$bug_url]}, test => 'Admin can add a URL to a public bug'},
    {user => 'unprivileged', args => {ids => ['public_bug'], remove => [$bug_url]}, error => 'only the assignee or reporter of the bug, or a user', test => 'Unprivileged user cannot remove a URL from a bug'},
    {user => 'admin', args => {ids => ['public_bug'], remove => [$bug_url]}, test => 'Admin can remove a URL from a public bug'},
    {user => PRIVATE_BUG_USER, args => {ids => ['private_bug'], add => [$bug_url]}, test => PRIVATE_BUG_USER . ' can add a URL to a private bug'},
    {user => PRIVATE_BUG_USER, args => {ids => ['private_bug'], remove => [$bug_url]}, test => PRIVATE_BUG_USER . ' can remove a URL from a private bug'},
  )
);

foreach my $test (@tests) {
  my $id = $test->{args}{ids}[0];
  my $api_key = $config->{"$test->{user}_user_api_key"};
  my $headers = api_headers($api_key);

  my %see_also;
  $see_also{add}    = $test->{args}{add}    if exists $test->{args}{add};
  $see_also{remove} = $test->{args}{remove} if exists $test->{args}{remove};
  my $body = {see_also => \%see_also};

  if (my $error = $test->{error}) {
    $t->put_ok($url . "rest/bug/$id" => $headers => json => $body)->status_isnt(200);
    like($t->tx->res->json->{message}, qr/\Q$error\E/, "$test->{test}: $error");
  }
  else {
    $t->put_ok($url . "rest/bug/$id" => $headers => json => $body)->status_is(200);
    isa_ok($t->tx->res->json->{bugs}->[0]->{changes}, 'HASH', "Changes");
  }
}

done_testing();
