#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
local $| = 1;

use constant BATCH_SIZE => 100;

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Util qw(trim);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $user = Bugzilla::User->check({name => 'automation@bmo.tld'});
$user->{groups}       = [Bugzilla::Group->get_all];
$user->{bless_groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($user);

my $dbh = Bugzilla->dbh;

# find the bugs
my $bugs = $dbh->selectall_arrayref(
  "SELECT bug_id, short_desc AS summary, cf_crash_signature FROM bugs WHERE resolution = '' AND cf_crash_signature != ''",
  {Slice => {}}
);
my $count = scalar @$bugs;

# update
die "No bugs found\n" unless $count;
print
  "Found $count open bug(s) with crash signatures\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
getc;

my $updated = 0;
foreach my $rh_bug (@$bugs) {
  my $bug_id    = $rh_bug->{bug_id};
  my $summary   = $rh_bug->{summary};
  my $signature = $rh_bug->{cf_crash_signature};

  # update summary
  my $updated_summary   = update_crash_signatures($summary);
  my $updated_signature = update_crash_signatures($signature);

  next
    if is_same($signature, $updated_signature)
    && is_same($summary,   $updated_summary);

  # update the bug, preventing bugmail
  print "Updating $bug_id\n";
  $dbh->bz_start_transaction;
  my $bug = Bugzilla::Bug->check($bug_id);
  $bug->set_all(
    {summary => $updated_summary, cf_crash_signature => $updated_signature});
  $bug->update();
  $dbh->do('UPDATE bugs SET lastdiffed = delta_ts WHERE bug_id = ?',
    undef, $bug_id);
  $dbh->bz_commit_transaction;

  # object caching causes us to consume a lot of memory
  # process in batches
  last if ++$updated == BATCH_SIZE;
}
print "Updated $updated bugs(s)\n";

sub is_same {
  my ($old, $new) = @_;
  $old =~ s/[\015\012]+/ /g;
  $new =~ s/[\015\012]+/ /g;
  return trim($old) eq trim($new);
}

sub update_crash_signatures {
  my $text = shift;
  $text =~ s/\[@ (.*?)\([^)]*\)\]/\[\@$1\]/igx;
  return $text;
}
