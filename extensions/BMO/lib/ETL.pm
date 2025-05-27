#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::BMO::ETL;

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Logging;
use Bugzilla::Extension::BMO::ETL::Export;

use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use IO::Async::Signal;
use Mojo::Util qw(dumper);
use Moo;
use Try::Tiny;

has 'is_daemon' => (is => 'rw', default => 0);

# ETL polling value
use constant ETL_TIMEOUT      => 60;
use constant ETL_POLL_SECONDS => 5;

sub start {
  my ($self, %options) = @_;

  DEBUG(dumper \%options);

  my $sig_alarm = IO::Async::Signal->new(
    name       => 'ALRM',
    on_receipt => sub {
      FATAL('Timeout reached while executing etl export');
      exit 1;
    },
  );

  # Query for new revisions or changes
  my $etl_timer = IO::Async::Timer::Periodic->new(
    first_interval => 0,
    interval       => ETL_POLL_SECONDS,
    reschedule     => 'drift',
    on_tick        => sub {
      try {
        alarm ETL_TIMEOUT;
        my $export = Bugzilla::Extension::BMO::ETL::Export->new(%options);
        $export->run_export;
      }
      catch {
        FATAL($_);
      }
      finally {
        alarm 0;
        try {
          Bugzilla->_cleanup();
        }
        catch {
          FATAL("Error in _cleanup: $_");
          exit 1;
        }
      };
    },
  );

  my $loop = IO::Async::Loop->new;
  $loop->add($etl_timer);
  $etl_timer->start;
  $loop->run;
}

1;
