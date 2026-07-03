# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Helpers shared by the rest_*.t REST API tests. These intentionally use
# Mojo (Test::Mojo) since that is the convention the REST tests are
# standardizing on.

package QA::REST::Util;

use 5.10.1;
use strict;
use warnings;

use Mojo::URL;
use Storable qw(dclone);
use Test::More;
use QA::Util qw(random_string);
use QA::Tests qw(create_bug_fields PRIVATE_BUG_USER);

use parent qw(Exporter);

our @EXPORT_OK = qw(
  api_headers
  rest_get_url
  create_test_bugs
  test_bug
);

# Return a header hashref that authenticates as the given API key.
# Pass undef/empty to get an empty (anonymous) header set.
sub api_headers {
  my ($api_key) = @_;
  return $api_key ? {'X-Bugzilla-API-Key' => $api_key} : {};
}

# Build a Mojo::URL for a GET request to the REST API, turning a params
# hashref into a query string. Array-ref values become repeated query keys
# (e.g. names => ['a','b'] -> names=a&names=b), which is how the Bugzilla
# WebService GET interface expects multi-valued parameters. undef values
# are skipped.
sub rest_get_url {
  my ($base, $path, $params) = @_;
  my $url = Mojo::URL->new($base . $path);
  my @query;
  foreach my $key (sort keys %{$params || {}}) {
    my $value = $params->{$key};
    next if !defined $value;
    if (ref $value eq 'ARRAY') {
      push @query, map { ($key => $_) } grep { defined $_ } @$value;
    }
    else {
      push @query, ($key => $value);
    }
  }
  $url->query(@query) if @query;
  return $url;
}

# Create a public and a second (optionally private) bug for use as test
# fixtures, via POST /rest/bug. Returns the two bug-field hashes with their
# new {id} filled in. Options: second_private => bool, no_cc => bool.
sub create_test_bugs {
  my ($t, $config, $url, %opt) = @_;

  my @whiteboard = map { random_string() } (1 .. 3);
  my @summary    = map { random_string() } (1 .. 3);

  my $public = create_bug_fields($config);
  delete $public->{cc} if $opt{no_cc};
  $public->{alias}      = random_string(40);
  $public->{whiteboard} = join(' ', @whiteboard);
  $public->{summary}    = join(' ', @summary);

  my $private = dclone($public);
  $private->{alias} = random_string(40);
  if ($opt{second_private}) {
    $private->{product}          = 'QA-Selenium-TEST';
    $private->{component}        = 'QA-Selenium-TEST';
    $private->{target_milestone} = 'QAMilestone';
    $private->{version}          = 'QAVersion';
    $private->{creator}          = $config->{PRIVATE_BUG_USER . '_user_login'};
  }

  $public->{id} = _create_one($t, $url, $config->{editbugs_user_api_key}, $public);
  my $private_key
    = $opt{second_private}
    ? $config->{PRIVATE_BUG_USER . '_user_api_key'}
    : $config->{editbugs_user_api_key};
  $private->{id} = _create_one($t, $url, $private_key, $private);

  return ($public, $private);
}

sub _create_one {
  my ($t, $url, $api_key, $fields) = @_;
  $t->post_ok(
    $url . 'rest/bug' => api_headers($api_key) => json => $fields)
    ->status_is(200);
  return $t->tx->res->json->{id};
}

# Compare a bug hash returned by the REST API against expected field values.
# $test is the test-case hashref (used for include_fields/exclude_fields).
sub test_bug {
  my ($fields, $bug, $expect, $test, $creation_time) = @_;

  # include_fields/exclude_fields are the same for every field, so build
  # them once rather than on every loop iteration.
  my @include = @{$test->{args}{include_fields} || []};
  my @exclude = @{$test->{args}{exclude_fields} || []};

  foreach my $field (sort @$fields) {

    # "description" is used by Bug.create but comments are not returned
    # by Bug.get or Bug.search.
    next if $field eq 'description';

    if ( (@include and !grep { $_ eq $field } @include)
      or (@exclude and grep { $_ eq $field } @exclude))
    {
      ok(!exists $bug->{$field}, "$field is not included");
      next;
    }

    if ($field =~ /^is_/) {
      ok(defined $bug->{$field}, "$field is not null");
      is($bug->{$field} ? 1 : 0, $expect->{$field} ? 1 : 0,
        "$field has the right boolean value");
    }
    elsif ($field eq 'cc') {
      foreach my $cc_item (@{$expect->{cc} || []}) {
        ok(grep({ $_ eq $cc_item } @{$bug->{cc}}), "$field contains $cc_item");
      }
    }
    elsif (($field eq 'creation_time' or $field eq 'last_change_time')
      and defined $creation_time)
    {
      my $creation_day = $creation_time->ymd;
      like(
        $bug->{$field},
        qr/^\Q${creation_day}\ET\d\d:\d\d:\d\d/,
        "$field has the right format"
      );
    }
    else {
      is_deeply($bug->{$field}, $expect->{$field}, "$field value is correct");
    }
  }
}

1;
