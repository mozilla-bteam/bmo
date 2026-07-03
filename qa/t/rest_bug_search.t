#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Test for REST call to Bug.search()                #
# GET /rest/bug                                      #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use QA::Util qw(get_config random_string);
use QA::Tests qw(PRIVATE_BUG_USER);
use QA::REST::Util qw(api_headers rest_get_url create_test_bugs);

use Test::Mojo;
use Test::More;

my $config = get_config();
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

my ($public_bug, $private_bug)
  = create_test_bugs($t, $config, $url, second_private => 1);

my @tests;
foreach my $field (keys %$public_bug) {
  next if ($field eq 'cc' or $field eq 'description');
  my $test
    = {args => {$field => $public_bug->{$field}}, test => "Search by $field"};
  if (grep($_ eq $field, qw(alias whiteboard summary))) {
    $test->{exactly} = 1;
    $test->{bugs}    = 1;
  }
  push(@tests, $test);
}

push(
  @tests,
  (
    {
      args  => {offset => 1},
      test  => "Offset without limit fails",
      error => 'requires a limit argument',
    },

    {
      args => {alias => $private_bug->{alias}},
      test => 'Logged-out cannot find a private_bug by alias',
      bugs => 0,
    },

    {args => {creation_time => '19700101T00:00:00'}, test => 'Get all bugs by creation time'},
    {args => {creation_time => '20380101T00:00:00'}, test => 'Get no bugs, by creation time', bugs => 0},
    {args => {last_change_time => '19700101T00:00:00'}, test => 'Get all bugs by last_change_time'},
    {args => {last_change_time => '20380101T00:00:00'}, test => 'Get no bugs by last_change_time', bugs => 0},

    {args => {reporter => $config->{editbugs_user_login}}, test => 'Search by reporter'},
    {args => {resolution => '---'}, test => 'Search for empty resolution',},
    {args => {resolution => 'NO_SUCH_RESOLUTION'}, test => 'Search for invalid resolution', bugs => 0},
    {args => {summary => substr($public_bug->{summary}, 0, 50)}, test => 'Search by partial summary', bugs => 1, exactly => 1},
    {args => {summary => random_string() . ' ' . random_string()}, test => 'Summary search that returns no results', bugs => 0},
    {args => {summary => [split(/\s/, $public_bug->{summary})]}, test => 'Summary search using multiple terms'},

    {args => {whiteboard => substr($public_bug->{whiteboard}, 0, 50)}, test => 'Search by partial whiteboard', bugs => 1, exactly => 1},
    {args => {whiteboard => random_string(100)}, test => 'Whiteboard search that returns no results', bugs => 0},
    {args => {whiteboard => [split(/\s/, $public_bug->{whiteboard})]}, test => 'Whiteboard search using multiple terms', bugs => 1, exactly => 1},

    {
      args => {
        product          => $public_bug->{product},
        component        => $public_bug->{component},
        last_change_time => '19700101T00:00:00'
      },
      test => 'Search by multiple arguments',
    },

    # Logged-in user who can see private bugs
    {
      user    => PRIVATE_BUG_USER,
      args    => {alias => [$public_bug->{alias}, $private_bug->{alias}]},
      test    => 'Search using two aliases (including one private)',
      bugs    => 2,
      exactly => 1,
    },
    {
      user => PRIVATE_BUG_USER,
      args =>
        {product => [$public_bug->{product}, $private_bug->{product}], limit => 1},
      test    => 'Limit 1',
      bugs    => 1,
      exactly => 1,
    },
    {
      user => PRIVATE_BUG_USER,
      args => {
        product => [$public_bug->{product}, $private_bug->{product}],
        limit   => 1,
        offset  => 1
      },
      test    => 'Limit 1 Offset 1',
      bugs    => 1,
      exactly => 1,
    },

    # include_fields and exclude_fields
    {
      args => {
        id             => $public_bug->{id},
        include_fields => ['id', 'alias', 'summary', 'groups']
      },
      test => 'include_fields',
    },
    {
      args =>
        {id => $public_bug->{id}, exclude_fields => ['assigned_to', 'cf_qa_status']},
      test => 'exclude_fields'
    },
    {
      args => {
        id             => $public_bug->{id},
        include_fields => ['id', 'alias', 'summary', 'groups'],
        exclude_fields => ['summary']
      },
      test => 'exclude_fields overrides include_fields'
    },
  )
);

# No fixture bug has a vote, so searching by votes must return an empty
# (but well-formed) result. bugs => 0 asserts exactly that.
push(@tests,
  {args => {votes => 1}, test => 'Search by votes', bugs => 0})
  if $config->{test_extensions};

sub check_search {
  my ($test, $json) = @_;
  my $bugs           = $json->{bugs};
  my $expected_count = $test->{bugs};
  $expected_count = 1 if !defined $expected_count;
  if ($expected_count) {
    my $operator = $test->{exactly} ? '==' : '>=';
    cmp_ok(scalar @$bugs,
      $operator, $expected_count, 'The right number of bugs are returned');
    unless ($test->{user} and $test->{user} eq PRIVATE_BUG_USER) {
      ok(!grep($_->{alias} && $_->{alias} eq $private_bug->{alias}, @$bugs),
        'Result does not contain the private bug');
    }

    my @include = @{$test->{args}->{include_fields} || []};
    my @exclude = @{$test->{args}->{exclude_fields} || []};
    if (@include or @exclude) {
      my @check_fields = uniq(keys %$public_bug, @include);
      foreach my $field (sort @check_fields) {
        next if $field eq 'description';
        if ( (@include and !grep { $_ eq $field } @include)
          or (@exclude and grep { $_ eq $field } @exclude))
        {
          ok(!exists $bugs->[0]->{$field}, "$field is not included")
            or diag Dumper($bugs);
        }
        else {
          ok(exists $bugs->[0]->{$field}, "$field is included");
        }
      }
    }
  }
  else {
    is(scalar @$bugs, 0, 'No bugs returned');
  }
}

foreach my $test (@tests) {
  my $api_key = $test->{user} ? $config->{"$test->{user}_user_api_key"} : undef;
  my $headers = api_headers($api_key);
  my $req     = rest_get_url($url, 'rest/bug', $test->{args});

  if (my $error = $test->{error}) {
    $t->get_ok($req => $headers)->status_isnt(200);
    like($t->tx->res->json->{message}, qr/\Q$error\E/, "$test->{test}: $error");
  }
  else {
    $t->get_ok($req => $headers)->status_is(200);
    check_search($test, $t->tx->res->json);
  }
}

done_testing();
