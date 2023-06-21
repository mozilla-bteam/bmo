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

use Bugzilla;

BEGIN {
  Bugzilla->extensions;
}

use Test2::V0 qw( done_testing ok );

use Bugzilla::Extension::SearchAPI::Util qw(named_params);

# Basic test (specific)
my $test_sql
  = 'SELECT id FROM bug_status WHERE value = :value AND isactive = :isactive';

my ($updated_sql, $values)
  = named_params($test_sql, {value => 'NEW', isactive => 1});

my $expected_sql = 'SELECT id FROM bug_status WHERE value = ? AND isactive = ?';

ok($updated_sql eq $expected_sql, 'SQL matches what is expected');
ok(scalar @$values == 2,          'Two values returned');
ok(
  $values->[0] eq 'NEW' && $values->[1] == 1,
  'First value is NEW and second value is 1'
);

# Test failure
($updated_sql, $values) = named_params($test_sql, {foo => 'bar'});
ok(!defined $updated_sql, 'Undefined returned instead of updated SQL');
ok(
  $values eq 'Parameter value not found for :value',
  'Error message matches what is expected'
);

# Basic test (list)
$test_sql = 'SELECT id FROM bug_status WHERE value IN (:value:)';

($updated_sql, $values)
  = named_params($test_sql, {value => ['NEW', 'RESOLVED']});

$expected_sql = 'SELECT id FROM bug_status WHERE value IN (?,?)';

ok($updated_sql eq $expected_sql, 'SQL matches what is expected');
ok(scalar @$values == 2,          'Two values returned');
ok(
  $values->[0] eq 'NEW' && $values->[1] eq 'RESOLVED',
  'First value is NEW and second value is RESOLVED'
);

# Test failure
($updated_sql, $values) = named_params($test_sql, {value => 'NEW'});
ok(!defined $updated_sql, 'Undefined returned instead of updated SQL');
ok($values eq 'Parameter value not found for :value: or not an array',
  'Error message matches what is expected');

done_testing;
