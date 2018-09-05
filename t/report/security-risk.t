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

my $bug1 = mock { id => 1 };

try {
    1;
    # my $report = Bugzilla::Report::SecurityRisk->new(
    #     start_date => DateTime->new( year => 2018, month => 7, day => 8 ),
    #     end_date => DateTime->new( year => 2018, month => 7, day => 8 ),
    #     products =>
    #     sec_keywords =>
    #     initial_bug_ids =>
    #     initial_bugs =>
    #     events =>
    # );

    # my $results = $report->results;

    # is_deeply($results->critical, { current => 0, previous => 2 },
    #     'two critical bugs became resolved (or non-critical)');
}
catch {
    fail('got an exception during main part of test');
    diag($_);
};


done_testing;
