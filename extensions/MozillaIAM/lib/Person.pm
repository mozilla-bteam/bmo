# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM::Person;

use 5.10.1;
use Moo;

use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use IO::Async::Signal;
use Try::Tiny;

use Bugzilla::Logging;
use Bugzilla::User;
use Bugzilla::Util qw(with_writable_database);
use Bugzilla::Extension::MozillaIAM::Constants;
use Bugzilla::Extension::MozillaIAM::Util qw(
  add_staff_member
  get_access_token
  get_profile_by_email
  get_profile_by_id
  remove_staff_member
);

has 'is_daemon' => (is => 'rw', default => 0);

my $CURRENT_QUERY = 'none';

sub run_query {
  my ($self, $name) = @_;
  my $method = $name . '_query';
  try {
    with_writable_database {
      alarm POLL_TIMEOUT;
      $CURRENT_QUERY = $name;
      $self->$method;
    };
  }
  catch {
    FATAL($_);
  }
  finally {
    alarm(0);
    $CURRENT_QUERY = 'none';
    try {
      Bugzilla->_cleanup();
    }
    catch {
      FATAL("Error in _cleanup: $_");
      exit 1;
    }
  };
}

sub start {
  my ($self) = @_;

  my $sig_alarm = IO::Async::Signal->new(
    name       => 'ALRM',
    on_receipt => sub {
      FATAL("Timeout reached while executing $CURRENT_QUERY query");
      exit 1;
    },
  );

  # Look for Mozilla accounts changes add by the CIS webhook
  my $cis_update_timer = IO::Async::Timer::Periodic->new(
    first_interval => 0,
    interval       => CIS_UPDATE_SECONDS,
    reschedule     => 'drift',
    on_tick        => sub { $self->run_query('cis_update') },
  );

  # Manually query for Mozilla account changes
  my $manual_update_timer = IO::Async::Timer::Periodic->new(
    first_interval => 0,
    interval       => MANUAL_UPDATE_SECONDS,
    reschedule     => 'drift',
    on_tick        => sub { $self->run_query('manual_update') },
  );

  my $loop = IO::Async::Loop->new;
  $loop->add($cis_update_timer);
  $loop->add($manual_update_timer);
  $loop->add($sig_alarm);

  $cis_update_timer->start;
  $manual_update_timer->start;

  $loop->run;
}

sub cis_update_query {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;

  local Bugzilla::Logging->fields->{type} = 'PERSON_API';

  # Ensure Mozilla IAM syncing is enabled
  if (!Bugzilla->params->{mozilla_iam_enabled}) {
    WARN('MOZILLA IAM SYNC DISABLED');
    return;
  }

  DEBUG('RUNNING CIS UPDATE QUERY');

  # We need to make the below changes as an empowered user
  my $restore_prev_user
    = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

  # Obtain access token for accessing the Person API
  my $access_token = get_access_token();
  if (!$access_token) {
    FATAL('Error obtaining access token');
    return;
  }

  # Find any updates that were inserted by the CIS system using a webhook
  my $cis_ids
    = $dbh->selectcol_arrayref(
    "SELECT value FROM mozilla_iam_updates WHERE type = 'update' ORDER BY mod_time"
    );

  foreach my $cis_id (@{$cis_ids}) {

    DEBUG("Processing updated user $cis_id");

    try {
      my $profile = get_profile_by_id($cis_id, $access_token);

      if ($profile && $profile->{iam_username}) {
        if (!$profile->{is_staff} || !$profile->{bmo_email}) {
          remove_staff_member({iam_username => $profile->{iam_username}});
        }

        if ($profile->{is_staff} && $profile->{bmo_email}) {
          add_staff_member({
            bmo_email    => $profile->{bmo_email},
            iam_username => $profile->{iam_username},
            real_name    => $profile->{first_name} . ' ' . $profile->{last_name},
            is_staff     => $profile->{is_staff},
          });
        }
      }
    }
    catch {
      WARN($_);
    }
    finally {
      # Remove from queue
      $dbh->do("DELETE FROM mozilla_iam_updates WHERE type = 'update' AND value = ?",
        undef, $cis_id);
    };
  }
}

sub manual_update_query {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;

  local Bugzilla::Logging->fields->{type} = 'PERSON_API';

  # Ensure Mozilla IAM syncing is enabled
  if (!Bugzilla->params->{mozilla_iam_enabled}) {
    WARN('MOZILLA IAM SYNC DISABLED');
    return;
  }

  DEBUG('RUNNING MANUAL UPDATE QUERY');

  # We need to make the below changes as an empowered user
  my $restore_prev_user
    = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

  # Obtain access token for accessing the Person API
  my $access_token = get_access_token();
  if (!$access_token) {
    FATAL('Error obtaining access token');
    return;
  }

  # Update current members
  my $rows = $dbh->selectall_arrayref(
    'SELECT user_id, iam_username FROM profiles_iam ORDER BY user_id');

  foreach my $row (@{$rows}) {
    my ($user_id, $iam_username) = @{$row};

    my $user = Bugzilla::User->new($user_id);
    DEBUG('Processing current user ' . $user->login);

    try {
      my $profile = get_profile_by_email($iam_username, $access_token);

      if ($profile && (!$profile->{is_staff} || !$profile->{bmo_email})) {
        remove_staff_member({user => $user});
      }
    }
    catch {
      WARN($_);
    };
  }
}

1;
