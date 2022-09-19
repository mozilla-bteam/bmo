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

# Bug 1789259 - Convert trivial, minor, normal, major+ (for crashes) severities to new style severity
#
# severity==trivial or severity==minor -> S4
# severity==normal -> S3
# (severity==major or severity==critical or severity==blocker) and (crash signature is not empty or "crash" is in keywords or product==Testing) -> S2
#

my @products = (
  'Calendar',
  'Chat Core',
  'Core',
  'Developer Infrastructure',
  'DevTools',
  'External Software Affecting Firefox',
  'Fenix',
  'Firefox Build System',
  'Firefox for iOS',
  'Firefox',
  'GeckoView',
  'JSS',
  'MailNews Core',
  'NSPR',
  'NSS',
  'Remote Protocol',
  'Testing',
  'Thunderbird',
  'Toolkit',
  'Web Compatibility',
  'WebExtensions',
);

my %severity_queries = (
  's2' => {
    product      => \@products,
    resolution   => '---',
    bug_severity => ['major', 'critical', 'blocker'],
    j_top        => 'OR',
    f1           => 'cf_crash_signature',
    o1           => 'isnotempty',
    f2           => 'keywords',
    o2           => 'equals',
    v2           => 'crash',
    f3           => 'product',
    o3           => 'equals',
    v3           => 'Testing',
  },
  's3' => {
    product      => \@products,
    resolution   => '---',
    bug_severity => ['normal'],
  },
  's4' => {
    product      => \@products,
    resolution   => '---',
    bug_severity => ['minor', 'trivial'],
  }
);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
$auto_user->{groups}       = [Bugzilla::Group->get_all];
$auto_user->{bless_groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($auto_user);

foreach my $new_severity (keys %severity_queries) {
  my $query = $severity_queries{$new_severity};

  # Show the buglist URL to to make it easier to sanity check
  my $url = URI->new('https://bugzilla.mozilla.org/buglist.cgi');
  $url->query_form(%$query);
  say $url;

  my $search = Bugzilla::Search->new(fields => ['bug_id'], params => $query,);
  my ($data) = $search->data;

  my $bug_count = @$data;
  if ($bug_count == 0) {
    warn "There are no bugs to update.\n\n";
    next;
  }

  print STDERR <<"EOF";
About to update $bug_count bugs by changing severity to $new_severity.

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

    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    # Update the severity
    my $bug = Bugzilla::Bug->new($bug_id);
    $bug->set_severity($new_severity);
    $bug->update($timestamp);

    $dbh->do("UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?",
      undef, $timestamp, $timestamp, $bug_id);

    # Tidy up
    Bugzilla::Hook::process('request_cleanup');
    Bugzilla::Bug->CLEANUP;
    Bugzilla->clear_request_cache(
      except => [qw(user dbh dbh_main dbh_shadow memcached)]);

    $dbh->bz_commit_transaction;
  }
}

Bugzilla->memcached->clear_all();
