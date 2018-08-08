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

my $ComponentMock = mock 'Bugzilla::Component' => (
    add_constructor => [ fake_new => 'hash' ],
);

my $bug1 = mock { id => 1 };
my $bug2 = mock { id => 2 };
my $bug3 = mock { id => 3 };

try {
    my $report = Bugzilla::Report::SecurityRisk->new(
        current_bugs => [
            $bug1,
            $bug2,
            $bug3,
        ],
        events => [
            # TODO
        ],
        # The next three things are probably not used because we pass in current_bugs and events.
        current_date  => DateTime->new( year => 2018, month => 7, day => 8 ),
        previous_date => DateTime->new( year => 2018, month => 7, day => 1 ),
        component     => Bugzilla::Component->fake_new(),
    );

    my $results = $report->results;

    is_deeply($results->critical, { current => 0, previous => 2 },
        'two critical bugs became resolved (or non-critical)');
    is_deeply($results->high, { current => 2, previous => 0 },
        'two critical high bugs appeared');
    is_deeply($results->moderate, { current => 0, previous => 0 },
        'moderate bugs stayed the same');
    is_deeply($results->low, { current => 10, previous => 0 },
        '10 low bugs happened');
    is_deeply($results->total, { current => 12, previous => 0 });
}
catch {
    fail('got an exception during main part of test');
    diag($_);
};


done_testing;
