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
use Bugzilla::Util qw(with_writable_database);
use Bugzilla::Extension::MozillaIAM::Constants;

has 'is_daemon' => (is => 'rw', default => 0);

my $CURRENT_QUERY = 'none';

sub run_query {
  my ($self, $name) = @_;
  my $method = $name . '_query';
  try {
    with_writable_database {
      alarm(PERSON_TIMEOUT);
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

      if (my $dd = Bugzilla->datadog) {
        my $lcname = lc $CURRENT_QUERY;
        $dd->increment("bugzilla.mozillaiam.${lcname}_query_timeouts");
      }

      exit 1;
    },
  );

  # Query for Mozilla account changes
  my $person_timer = IO::Async::Timer::Periodic->new(
    first_interval => 0,
    interval       => PERSON_POLL_SECONDS,
    reschedule     => 'drift',
    on_tick        => sub { $self->run_query('person') },
  );

  my $loop = IO::Async::Loop->new;
  $loop->add($person_timer);
  $loop->add($sig_alarm);

  $person_timer->start;

  $loop->run;
}

sub person_query {
  my ($self) = @_;

  local Bugzilla::Logging->fields->{type} = 'PERSON_API';

  # Ensure Mozilla IAM syncing is enabled
  if (!Bugzilla->params->{mozilla_iam_enabled}) {
    WARN("MOZILLA IAM SYNC DISABLED");
    return;
  }

  DEBUG('RUNNING PERSON QUERY');
}

1;
