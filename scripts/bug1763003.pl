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
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $rows = $dbh->selectall_arrayref(q{
  SELECT id, bug_id, added, removed
    FROM bugs_activity
   WHERE fieldid = 38 AND (added LIKE '%? %' OR removed LIKE '%? %')
});

my $row_count = @$rows;
if ($row_count == 0) {
  warn "There are no bugs_activity entries to update.\n";
  exit 1;
}

print STDERR <<EOF;
About to update $row_count entries in bugs_activity.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

$dbh->bz_start_transaction;

foreach my $row (@$rows) {
  my ($id, $bug_id, $added, $removed) = @$row;
  warn "Processing entry $id: $bug_id, '$added' <=> '$removed'\n";
  $added =~ s/[?] //g;
  $removed =~ s/[?] //g;
  warn "Updating to: '$added' <=> '$removed'\n";
  $dbh->do('UPDATE bugs_activity SET added = ?, removed = ? WHERE id = ?',
    undef, $added, $removed, $id);
}

$dbh->bz_commit_transaction;
