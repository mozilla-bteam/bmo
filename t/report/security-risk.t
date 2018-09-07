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
use Bugzilla;

BEGIN { Bugzilla->extensions };

use Test::More;
use Test2::Tools::Mock;
use Try::Tiny;

use ok 'Bugzilla::Report::SecurityRisk';
can_ok('Bugzilla::Report::SecurityRisk', qw(new results));

try {
    use Bugzilla::Report::SecurityRisk;
    my $report = Bugzilla::Report::SecurityRisk->new(
        start_date => DateTime->new( year => 2000, month => 1, day => 2 ),
        end_date => DateTime->new( year => 2000, month => 1, day => 30 ),
        products => ['Firefox', 'Core'],
        sec_keywords => ['sec-critical', 'sec-high'],
        initial_bug_ids => [1, 2, 3],
        initial_bugs => 1,
        events => 1,
    );
    my $results = $report->results;

    # Test dates
    my @expected_dates = (
        DateTime->new( year => 2000, month => 1, day => 2 ),
        DateTime->new( year => 2000, month => 1, day => 9 ),
        DateTime->new( year => 2000, month => 1, day => 16 ),
        DateTime->new( year => 2000, month => 1, day => 23 ),
        DateTime->new( year => 2000, month => 1, day => 30 ),
    );
    my @actual_dates = map { $_->{date} } @$results;
    is(@actual_dates, @expected_dates, 'Report Week Dates Are Correct');

    # Test bugs
}
catch {
    fail('got an exception during main part of test');
    diag($_);
};

done_testing;
