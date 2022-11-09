# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Bloomfilter;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;

use Algorithm::BloomFilter;
use Mojo::File qw(path);

sub _new_bloom_filter {
  my ($n) = @_;
  my $p   = 0.01;
  my $m   = $n * abs(log $p) / log(2)**2;
  my $k   = $m / $n * log(2);
  return Algorithm::BloomFilter->new($m, $k);
}

sub populate {
  my ($class, $name, $file) = @_;
  my $dbh       = Bugzilla->dbh;
  my $memcached = Bugzilla->memcached;

  # Load values from file, one per row
  my @values = split /\n/, path($file)->slurp;

  # Put items in database
  foreach my $value (@values) {
    my $exists
      = $dbh->selectrow_array(
      'SELECT value FROM bloomfilter_values WHERE name = ? AND value = ?',
      undef, $name, $value);
    if (!$exists) {
      $dbh->do('INSERT INTO bloomfilter_values (name, value) VALUES (?, ?)',
        undef, $name, $value);
    }
  }

  $memcached->clear_bloomfilter({name => $name});
}

sub lookup {
  my ($class, $name) = @_;
  my $memcached   = Bugzilla->memcached;
  my $filter_data = $memcached->get_bloomfilter({name => $name});

  if (!$filter_data) {

    # Read filter values from database
    my $values
      = Bugzilla->dbh->selectcol_arrayref(
      'SELECT value FROM bloomfilter_values WHERE name = ?',
      undef, $name);
    if (@$values) {
      my $filter = _new_bloom_filter(@$values + 0);
      $filter->add($_) foreach @$values;
      $filter_data = $filter->serialize;
      $memcached->set_bloomfilter({name => $name, filter => $filter_data});
    }
  }

  return Algorithm::BloomFilter->deserialize($filter_data) if $filter_data;
  return undef;
}

1;
