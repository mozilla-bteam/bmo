#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License,  v. 2.0. If a copy of the MPL was not distributed with this
# file,  You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses",  as
# defined by the Mozilla Public License,  v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trim);

BEGIN {
  Bugzilla->extensions;
}

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# User to make changes as automation@bmo.tld
my $auto_user = Bugzilla::User->new({name => 'automation@bmo.tld'});
$auto_user || usage("Can't find user 'automation\@bmo.tld'\n");
$auto_user->{groups}       = [Bugzilla::Group->get_all];
$auto_user->{bless_groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($auto_user);

Bugzilla::Extension::TrackingFlags::Flag->get_all;    # preload

# Load fields information (assumes already created)
my $flag_field = Bugzilla::Extension::TrackingFlags::Flag->check(
  {name => 'cf_accessibility_severity'});
my $whiteboard_field = Bugzilla::Field->check({name => 'status_whiteboard'});

my $dbh = Bugzilla->dbh;

my $rows = $dbh->selectall_arrayref(
  "SELECT bugs.bug_id, bugs.status_whiteboard FROM bugs WHERE "
    . $dbh->sql_regexp('bugs.status_whiteboard', $dbh->quote('\[access-s\d+\]'))
);

my $bug_count = scalar @{$rows};
$bug_count || die "No bugs were found in matching search criteria.\n";

print STDERR <<"EOF";
About to update $bug_count bugs.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc;

$dbh->bz_start_transaction();

foreach my $row (@{$rows}) {
  my ($bug_id, $whiteboard) = @{$row};

  print "Working on bug $bug_id\n";

  my $bug = Bugzilla::Bug->new($bug_id);

  my ($severity) = $whiteboard =~ /\[access-(s\d+)\]/;
  $severity ||= '';

  my $severity_found = 0;
  foreach my $value (@{$flag_field->values}) {
    if ($value->value eq $severity) {
      $severity_found = 1;
      last;
    }
  }

  my $set_all = {};
  if ($severity_found) {
    print "  updating flag value for cf_accessibility_severity to $severity\n";
    $set_all->{'cf_accessibility_severity'} = $severity;
  }
  else {
    print "  severity $severity does not exist ... skipping\n";
    next;
  }

  $whiteboard =~ s/\[access-$severity\]//;
  $set_all->{status_whiteboard} = $whiteboard;
  print "  updating whiteboard to '$whiteboard'\n";

  $bug->set_all($set_all);
  $bug->update();

  # Updated lastdiffed timestamp so the change is not included in email notifications
  $dbh->do('UPDATE bugs SET lastdiffed = NOW() WHERE bug_id = ?', undef, $bug->id);
}

$dbh->bz_commit_transaction();
