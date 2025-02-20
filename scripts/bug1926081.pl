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
use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);

use List::Util qw(max);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $sth = $dbh->prepare(
  'UPDATE profiles SET modification_ts = FROM_UNIXTIME(?) WHERE userid = ?');

# Todays timestamp
my $now_when
  = $dbh->selectrow_array('SELECT UNIX_TIMESTAMP(LOCALTIMESTAMP(0))');

my $user_ids = $dbh->selectcol_arrayref(
  'SELECT userid FROM profiles WHERE modification_ts IS NULL ORDER BY userid');

my $count = 1;
my $total = scalar @{$user_ids};

foreach my $user_id (@{$user_ids}) {
  indicate_progress({total => $total, current => $count++, every => 25});

  my $audit_log_when = $dbh->selectrow_array(
    'SELECT UNIX_TIMESTAMP(at_time) FROM audit_log
      WHERE class = \'Bugzilla::User\' AND object_id = ? ORDER BY at_time DESC '
      . $dbh->sql_limit(1), undef, $user_id
  );
  my $profiles_act_when = $dbh->selectrow_array(
    'SELECT UNIX_TIMESTAMP(profiles_when) FROM profiles_activity
      WHERE userid = ? ORDER BY profiles_when DESC '
      . $dbh->sql_limit(1), undef, $user_id
  );

  my $creation_when
    = $dbh->selectrow_array(
    'SELECT UNIX_TIMESTAMP(creation_ts) FROM profiles WHERE userid = ?',
    undef, $user_id);

  $creation_when     ||= 0;
  $audit_log_when    ||= 0;
  $profiles_act_when ||= 0;

  my $modification_ts = 0;

  # IF we could not find anything then use todays date
  if (!$audit_log_when && !$profiles_act_when && !$creation_when) {
    $modification_ts = $now_when;
  }

# We used unix timestamps to make value comparison easier without using DateTime instance of each.
  else {
    $modification_ts = max($audit_log_when, $profiles_act_when, $creation_when);
  }

  $sth->execute($modification_ts, $user_id);
}

$dbh->bz_alter_column('profiles', 'modification_ts',
  {TYPE => 'DATETIME', NOTNULL => 1});

1;
