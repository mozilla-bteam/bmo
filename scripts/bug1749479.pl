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

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
$auto_user->{groups}       = [Bugzilla::Group->get_all];
$auto_user->{bless_groups} = [Bugzilla::Group->get_all];
Bugzilla->set_user($auto_user);

my $query = {
  f1 => 'regressed_by',
  o1 => 'isnotempty',

  f2 => 'OP',
  j2 => 'OR',

  f3 => 'keywords',
  o3 => 'notequals',
  v3 => 'regression',

  f4 => 'cf_has_regression_range',
  o4 => 'equals',
  v4 => '---',

  f5 => 'CP',
};

my $search = Bugzilla::Search->new(fields => ['bug_id'], params => $query,);
my ($data) = $search->data;

my $bug_count = @$data;
if ($bug_count == 0) {
  warn "There are no bugs to update.\n";
  exit 1;
}

print STDERR <<EOF;
About to update $bug_count bugs by adding regression keyword
and updating has regression range custom field.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

my $regression_field
  = Bugzilla::Field->check({name => 'cf_has_regression_range'});
my $regression_keyword = Bugzilla::Keyword->check({name => 'regression'});

foreach my $row (@$data) {
  my $bug_id = shift @$row;
  warn "Updating bug $bug_id\n";

  $dbh->bz_start_transaction;

  # Bug changes
  my $bug           = Bugzilla::Bug->new($bug_id);
  my $last_delta_ts = $bug->delta_ts;

  my $regressed_by_ts = $dbh->selectrow_array(
    'SELECT bug_when FROM bugs_activity
      WHERE bug_id = ?
            AND fieldid = (SELECT id FROM fielddefs WHERE name = \'regressed_by\')
            AND added IS NOT NULL
      ORDER BY bug_when DESC LIMIT 1', undef, $bug->id
  );

  # If no timestamp was found in the activity table, it was added
  # at the time the bug was created. In this case we will just use
  # the current last modified timestamp.
  if (!$regressed_by_ts) {
    $regressed_by_ts = $bug->delta_ts;
  }

  # Do not change if already set to something other than '---'
  if ($bug->cf_has_regression_range eq '---') {
    $bug->set_custom_field($regression_field, 'yes');
  }

  $bug->modify_keywords(['regression'], 'add');
  $bug->update($regressed_by_ts);

  $dbh->do('UPDATE bugs SET delta_ts = ? WHERE bug_id = ?',
    undef, $last_delta_ts, $bug->id);

  # Make sure memory is cleaned up.
  Bugzilla::Hook::process('request_cleanup');
  Bugzilla::Bug->CLEANUP;
  Bugzilla->clear_request_cache(
    except => [qw(user dbh dbh_main dbh_shadow memcached)]);

  $dbh->bz_commit_transaction;
}

Bugzilla->memcached->clear_all();
