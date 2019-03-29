#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

use Test2::V0;
use Test2::Tools::Mock qw(mock mock_accessor);
use Test2::Tools::Exception qw(dies lives);
use Bugzilla::Report::Graph;

my $DB = mock 'Bugzilla::DB' => (
  add_constructor => [
    fake_new => 'hash'
  ]
);

my $dbh    = Bugzilla::DB->fake_new;
my $report = Bugzilla::Report::Graph->new(
  dbh    => $dbh,
  bug_id => 1,
  paths  => [
    [1, grep { ($_ % 3) == 0 } 1..42],
    [map { 2**$_ } 0..10],
    [
      1,   2,   3,   5,   7,   11,  13,  17,  19,  23,  29,  31,
      37,  41,  43,  47,  53,  59,  61,  67,  71,  73,  79,  83,
      89,  97,  101, 103, 107, 109, 113, 127, 131, 137, 139, 149,
      151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199
    ],
    [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144],
  ]
);

like($report->graph, qr/\b197-/, "found link from 197");
like($report->graph, qr/-197\b/, "found link to 197");
like($report->graph, qr/\b199\b/, "found descendent of 197");

my $pruned = $report->prune_graph(sub {
  my ($ids) = @_;
  return [grep { $_ != 197 } @$ids]
});
is([197, 199], [ @$pruned ], "verify what was pruend");

unlike($report->graph, qr/\b197-/, "did not find link from 197");
unlike($report->graph, qr/-197\b/, "did not find link to 197");
unlike($report->graph, qr/\b199\b/, "did not find descendent of 197");

done_testing;


