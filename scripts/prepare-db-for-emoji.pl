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

use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), ".."));
    lib->import($dir, File::Spec->catdir($dir, "lib"), File::Spec->catdir($dir, qw(local lib perl5)));
    chdir $dir;
}

use Bugzilla;
use Bugzilla::Constants;

BEGIN { Bugzilla->extensions }

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my %mysql_var = map { @$_ } @{ $dbh->selectall_arrayref(q(SHOW GLOBAL VARIABLES LIKE 'innodb_%')) };
my %wanted = (
    innodb_file_format    => 'Barracuda',
    innodb_file_per_table => 'ON',
    innodb_large_prefix   => 'ON',
);

my $can_convert = 1;
foreach my $key (keys %wanted) {
    unless ($mysql_var{$key} eq $wanted{$key}) {
        warn "$key must be set to $wanted{$key} (current value is $mysql_var{$key})\n";
        $can_convert = 0;
    }
}
die "Unable to convert from COMPACT to DYNAMIC\n" unless $can_convert;

my $tables = $dbh->selectall_arrayref('SHOW TABLE STATUS');

foreach my $table (@$tables) {
    my ($table, undef, undef, $row_format) = @$table;
    if ($row_format ne 'Dynamic') {
        say "Converting $table...";
        say "ALTER TABLE $table ROW_FORMAT=DYNAMIC";
        $dbh->do("ALTER TABLE $table ROW_FORMAT=DYNAMIC");
        say "done.";
    }
}

