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
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Search;
use Getopt::Long;
use URI qw();

BEGIN { Bugzilla->extensions(); }

# Bug 1764246
# Use "triaged" keyword to track bug's triaged state instead of severity
#
# Adds triaged keyword to open Firefox bugs with a valid severity set.

use Bugzilla::Extension::BMO::Data qw(@triage_keyword_products);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
$auto_user->{groups}       = [Bugzilla::Group->get_all];
$auto_user->{bless_groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($auto_user);

my $query = {
  product       => \@triage_keyword_products,
  resolution    => '---',
  keywords      => 'triaged',
  keywords_type => 'nowords',
  f1            => 'bug_severity',
  o1            => 'notequals',
  v1            => '--',
};

# Show the buglist URL to to make it easier to sanity check
my $url = URI->new('https://bugzilla.mozilla.org/buglist.cgi');
$url->query_form(%$query);
say "$url\n";

my $search = Bugzilla::Search->new(fields => ['bug_id'], params => $query,);
my ($data) = $search->data;

my $bug_count = @$data;
if ($bug_count == 0) {
  warn "There are no bugs to update.\n";
  exit 1;
}

print STDERR <<"EOF";
About to update $bug_count bugs by adding the triaged keyword.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

my $severity_fieldid = Bugzilla::Field->check({name => 'bug_severity'})->id;

my $i = 0;
foreach my $row (@$data) {
  $i++;
  my $bug_id = shift @$row;
  warn "$i/$bug_count Bug $bug_id\n";

  $dbh->bz_start_transaction;

  my $bug      = Bugzilla::Bug->new($bug_id);
  my $delta_ts = $bug->delta_ts;

  # Add the keyword
  $bug->modify_keywords(['triaged'], 'add');

  # Find the timestamp when severity was first set to a S* value
  my $triaged_ts = $dbh->selectrow_array(
    "SELECT bug_when FROM bugs_activity
      WHERE bug_id = ?
            AND fieldid = $severity_fieldid
            AND added IS NOT NULL
            AND added LIKE 'S%'
      ORDER BY bug_when ASC LIMIT 1", undef, $bug->id
  );

  # If no timestamp was found in the activity table, it was added
  # at the time the bug was created
  $triaged_ts ||= $bug->creation_ts;

  # Update database, using the triaged timestamp as the delta_ts; mostly for
  # the bugs_activity entry, but this will also set the bug's delta_ts
  $bug->update($triaged_ts);

  # Restore bug's delta_ts to its original value
  $dbh->do('UPDATE bugs SET delta_ts = ? WHERE bug_id = ?',
    undef, $delta_ts, $bug->id);

  # Tidy up
  Bugzilla::Hook::process('request_cleanup');
  Bugzilla::Bug->CLEANUP;
  Bugzilla->clear_request_cache(
    except => [qw(user dbh dbh_main dbh_shadow memcached)]);

  $dbh->bz_commit_transaction;
}

Bugzilla->memcached->clear_all();
