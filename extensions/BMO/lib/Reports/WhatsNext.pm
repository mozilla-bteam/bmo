# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::WhatsNext;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Search;
use Bugzilla::Status qw(BUG_STATE_OPEN);
use Bugzilla::User;
use Bugzilla::Util qw(datetime_from fetch_product_versions time_ago);

use DateTime;
use Mojo::Util qw(dumper);
use Try::Tiny;

use constant CLASSIFICATIONS => (
  'Client Software',
  'Developer Infrastructure',
  'Components',
  'Server Software',
  'Other',
);

use constant SELECT =>
  'SELECT bugs.bug_id, bugs.bug_status, bugs.priority, bugs.bug_severity, bugs.short_desc, bugs.delta_ts';

# Wrap the sql execution in a try block so we can see any SQL errors in debug output
sub get_bug_list {
  my ($query, @values) = @_;
  try {
    return Bugzilla->dbh->selectall_arrayref($query, {Slice => {}}, @values);
  }
  catch {
    DEBUG($_);
    return [];
  };
}

sub format_bug_list {
  my ($bugs, $user) = @_;

  my $datetime_now = DateTime->now(time_zone => $user->timezone);

  my @formatted_bugs;
  foreach my $row (@{$bugs}) {
    my $bug = {
      id          => $row->{bug_id},
      status      => $row->{bug_status},
      priority    => $row->{priority},
      severity    => $row->{bug_severity},
      summary     => $row->{short_desc},
      changeddate => $row->{delta_ts},
    };
    my $datetime = datetime_from($bug->{changeddate});
    $datetime->set_time_zone($user->timezone);
    $bug->{changeddate}       = $datetime->strftime('%Y-%m-%d %T %Z');
    $bug->{changeddate_fancy} = time_ago($datetime, $datetime_now);
    push @formatted_bugs, $bug;
  }

  return \@formatted_bugs;
}

sub filter_secure_bugs {
  my $bugs = shift;
  my $user = Bugzilla->user;    # Must be the current user

  # Running this will prime the visible bugs cache which
  # makes each loop of $user->can_see_bug a fast operation
  $user->visible_bugs([map { $_->{id} } @{$bugs}]);

  my @filtered_bugs;
  foreach my $bug (@{$bugs}) {
    next if !$user->can_see_bug($bug->{id});
    push @filtered_bugs, $bug;
  }

  return \@filtered_bugs;
}

# Here we fetch the latest versions so we can map then to
# the appropriate tracking and status flags.
sub get_tracking_status_flags {
  my $versions = fetch_product_versions('firefox');
  return {} unless $versions;

  my $nightly_version = $versions->{FIREFOX_NIGHTLY};
  my $beta_version    = $versions->{LATEST_FIREFOX_RELEASED_DEVEL_VERSION};
  my $release_version = $versions->{LATEST_FIREFOX_VERSION};
  return {} if !$nightly_version || !$beta_version || !$release_version;

  # We just want the major versions number
  my ($nightly_major) = $nightly_version =~ /^(\d+)/;
  my ($beta_major)    = $beta_version    =~ /^(\d+)/;
  my ($release_major) = $release_version =~ /^(\d+)/;
  return {} if !$nightly_major && !$beta_major && !$release_major;

  my $flag_data = {};

  # Tracking Flags
  my $nightly_name = "cf_tracking_firefox$nightly_major";
  my $beta_name    = "cf_tracking_firefox$beta_major";
  my $release_name = "cf_tracking_firefox$release_major";

  my $nightly_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $nightly_name});
  my $beta_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $beta_name});
  my $release_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $release_name});
  return {} if !$nightly_field && !$beta_field && !$release_field;

  $flag_data->{tracking}
    = {nightly => $nightly_field, beta => $beta_field, release => $release_field,
    };

  # Status Flags
  $nightly_name = "cf_status_firefox$nightly_major";
  $beta_name    = "cf_status_firefox$beta_major";
  $release_name = "cf_status_firefox$release_major";

  $nightly_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $nightly_name});
  $beta_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $beta_name});
  $release_field
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $release_name});
  return {} if !$nightly_field && !$beta_field && !$release_field;

  $flag_data->{status} = {
    nightly => $nightly_field,
    beta    => $beta_field,
    release => $release_field,
  };

  return $flag_data;
}

# S1 defects assigned to you
sub s1_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  # Preselected values for inserting into SQL
  my $cache      = Bugzilla->process_cache->{whats_next};
  my $class_ids  = join ',', @{$cache->{classification_ids}};
  my $bug_states = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
        WHERE products.classification_id IN ($class_ids)
              AND bugs.bug_severity = 'S1'
              AND bugs.bug_type = 'defect'
              AND bugs.bug_status IN ($bug_states)
              AND bugs.assigned_to = ?
     ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# sec-crit bugs assigned to you (these should already be S1 defects, but just in case…)
sub sec_crit_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  # Preselected values for inserting into SQL
  my $cache      = Bugzilla->process_cache->{whats_next};
  my $keyword_id = $cache->{sec_critical_id};
  my $class_ids  = join ',', @{$cache->{classification_ids}};
  my $bug_states = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              JOIN keywords ON bugs.bug_id = keywords.bug_id
        WHERE products.classification_id IN ($class_ids)
              AND keywords.keywordid = $keyword_id
              AND bugs.bug_status IN ($bug_states)
              AND bugs.assigned_to = ?
     ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# Bugs that are needinfo? you and are marked as being tracked against or blocking the current nightly/beta/release
sub important_needinfo_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  my $flags = get_tracking_status_flags();
  return [] if !exists $flags->{tracking};

  # Preselected values for inserting into SQL
  my $cache           = Bugzilla->process_cache->{whats_next};
  my $needinfo_id     = $cache->{needinfo_flag_id};
  my $class_ids       = join ',', @{$cache->{classification_ids}};
  my $bug_states      = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;
  my $nightly_flag_id = $flags->{tracking}->{nightly}->flag_id;
  my $beta_flag_id    = $flags->{tracking}->{beta}->flag_id;
  my $release_flag_id = $flags->{tracking}->{release}->flag_id;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_1
                ON bugs.bug_id = tracking_flags_bugs_1.bug_id
                AND tracking_flags_bugs_1.tracking_flag_id = $nightly_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_2
                ON bugs.bug_id = tracking_flags_bugs_2.bug_id
                AND tracking_flags_bugs_2.tracking_flag_id = $beta_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_3
                ON bugs.bug_id = tracking_flags_bugs_3.bug_id
                AND tracking_flags_bugs_3.tracking_flag_id = $release_flag_id
              LEFT JOIN flags AS requestees_login_name ON bugs.bug_id = requestees_login_name.bug_id
                AND COALESCE(requestees_login_name.requestee_id, 0) = ?
        WHERE products.classification_id IN ($class_ids)
              AND bugs.bug_status IN ($bug_states)
              AND (COALESCE(tracking_flags_bugs_1.value, '---') IN ('+', 'blocking')
                    OR COALESCE(tracking_flags_bugs_2.value, '---') IN ('+', 'blocking')
                    OR COALESCE(tracking_flags_bugs_3.value, '---') IN ('+', 'blocking'))
              AND (requestees_login_name.bug_id IS NOT NULL
                    AND requestees_login_name.type_id = $needinfo_id)
            ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# S2 defects assigned to you (for things that are not disabled in the current release)
sub s2_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  my $flags = get_tracking_status_flags();
  return [] if !exists $flags->{status};

  # Preselected values for inserting into SQL
  my $cache           = Bugzilla->process_cache->{whats_next};
  my $class_ids       = join ',', @{$cache->{classification_ids}};
  my $bug_states      = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;
  my $nightly_flag_id = $flags->{status}->{nightly}->flag_id;
  my $beta_flag_id    = $flags->{status}->{beta}->flag_id;
  my $release_flag_id = $flags->{status}->{release}->flag_id;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_1
                ON bugs.bug_id = tracking_flags_bugs_1.bug_id
                AND tracking_flags_bugs_1.tracking_flag_id = $nightly_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_2
                ON bugs.bug_id = tracking_flags_bugs_2.bug_id
                AND tracking_flags_bugs_2.tracking_flag_id = $beta_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_3
                ON bugs.bug_id = tracking_flags_bugs_3.bug_id
                AND tracking_flags_bugs_3.tracking_flag_id = $release_flag_id
        WHERE products.classification_id IN ($class_ids)
              AND bugs.bug_severity = 'S2'
              AND bugs.bug_status IN ($bug_states)
              AND bugs.assigned_to = ?
              AND COALESCE(tracking_flags_bugs_1.value, '---') != 'disabled'
              AND COALESCE(tracking_flags_bugs_2.value, '---') != 'disabled'
              AND COALESCE(tracking_flags_bugs_3.value, '---') != 'disabled'
            ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# sec-high bugs assigned to you (again, for things that are not disabled in the current release)
sub sec_high_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  my $flags = get_tracking_status_flags();
  return [] if !exists $flags->{status};

  # Preselected values for inserting into SQL
  my $cache           = Bugzilla->process_cache->{whats_next};
  my $keyword_id      = $cache->{sec_high_id};
  my $class_ids       = join ',', @{$cache->{classification_ids}};
  my $bug_states      = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;
  my $nightly_flag_id = $flags->{status}->{nightly}->flag_id;
  my $beta_flag_id    = $flags->{status}->{beta}->flag_id;
  my $release_flag_id = $flags->{status}->{release}->flag_id;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              JOIN keywords ON bugs.bug_id = keywords.bug_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_1
                ON bugs.bug_id = tracking_flags_bugs_1.bug_id
                AND tracking_flags_bugs_1.tracking_flag_id = $nightly_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_2
                ON bugs.bug_id = tracking_flags_bugs_2.bug_id
                AND tracking_flags_bugs_2.tracking_flag_id = $beta_flag_id
              LEFT JOIN tracking_flags_bugs AS tracking_flags_bugs_3
                ON bugs.bug_id = tracking_flags_bugs_3.bug_id
                AND tracking_flags_bugs_3.tracking_flag_id = $release_flag_id
        WHERE products.classification_id IN ($class_ids)
              AND keywords.keywordid = $keyword_id
              AND bugs.bug_status IN ($bug_states)
              AND bugs.assigned_to = ?
              AND COALESCE(tracking_flags_bugs_1.value, '---') != 'disabled'
              AND COALESCE(tracking_flags_bugs_2.value, '---') != 'disabled'
              AND COALESCE(tracking_flags_bugs_3.value, '---') != 'disabled'
            ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# Regressions
sub regression_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  # Preselected values for inserting into SQL
  my $cache      = Bugzilla->process_cache->{whats_next};
  my $keyword_id = $cache->{regression_id};
  my $class_ids  = join ',', @{$cache->{classification_ids}};
  my $bug_states = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              JOIN keywords ON bugs.bug_id = keywords.bug_id
        WHERE products.classification_id IN ($class_ids)
              AND keywords.keywordid = $keyword_id
              AND bugs.bug_status IN ($bug_states)
              AND bugs.assigned_to = ?
     ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

# Other needinfos (needinfos for me but not set by me)
sub other_needinfo_bugs {
  my $user = shift;
  my $dbh  = Bugzilla->dbh;

  # Cached values for inserting into SQL
  my $cache       = Bugzilla->process_cache->{whats_next};
  my $needinfo_id = $cache->{needinfo_flag_id};
  my $class_ids   = join ',', @{$cache->{classification_ids}};
  my $bug_states  = join ',', map { $dbh->quote($_) } BUG_STATE_OPEN;

  my $query = SELECT . "
         FROM bugs JOIN products ON bugs.product_id = products.id
              LEFT JOIN flags AS requestees_login_name ON bugs.bug_id = requestees_login_name.bug_id
                AND COALESCE(requestees_login_name.requestee_id, 0) = ?
                AND COALESCE(requestees_login_name.setter_id, 0) != ?
        WHERE products.classification_id IN ($class_ids)
              AND bugs.bug_status IN ($bug_states)
              AND (requestees_login_name.bug_id IS NOT NULL
                    AND requestees_login_name.type_id = $needinfo_id)
        ORDER BY bugs.delta_ts, bugs.bug_id";

  my $bugs           = get_bug_list($query, $user->id, $user->id);
  my $formatted_bugs = format_bug_list($bugs, $user);
  my $filtered_bugs  = filter_secure_bugs($formatted_bugs);

  return $filtered_bugs;
}

sub report {
  my $vars  = shift;
  my $user  = Bugzilla->user;
  my $input = Bugzilla->input_params;

  # If a username was not passed using the form, we default
  # to the current user.
  my $who
    = $input->{who} ? Bugzilla::User->check({name => $input->{who}}) : $user;

  # Here we load some values into cache that will be used later
  # by the various queries.
  my $cache = Bugzilla->process_cache->{whats_next} = {};
  my $dbh   = Bugzilla->dbh;

  # classifications
  $cache->{classification_ids} ||= $dbh->selectcol_arrayref('
    SELECT id
      FROM classifications
     WHERE name IN (' . join(', ', map { $dbh->quote($_) } CLASSIFICATIONS) . ')');

  # needinfo flag
  $cache->{needinfo_flag_id} ||= $dbh->selectrow_array("
    SELECT id FROM flagtypes WHERE name = 'needinfo'");

  # keyword ids
  $cache->{sec_critical_id} ||= $dbh->selectrow_array("
    SELECT id FROM keyworddefs WHERE name = 'sec-critical'");
  $cache->{sec_high_id} ||= $dbh->selectrow_array("
    SELECT id FROM keyworddefs WHERE name = 'sec-high'");
  $cache->{regression_id} ||= $dbh->selectrow_array("
    SELECT id FROM keyworddefs WHERE name = 'regression'");

  $vars->{who}                     = $who->login;
  $vars->{s1_bugs}                 = s1_bugs($who);
  $vars->{sec_crit_bugs}           = sec_crit_bugs($who);
  $vars->{important_needinfo_bugs} = important_needinfo_bugs($who);
  $vars->{s2_bugs}                 = s2_bugs($who);
  $vars->{sec_high_bugs}           = sec_high_bugs($who);
  $vars->{regression_bugs}         = regression_bugs($who);
  $vars->{other_needinfo_bugs}     = other_needinfo_bugs($who);
}

1;
