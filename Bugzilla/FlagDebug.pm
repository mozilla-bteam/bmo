# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# TEMPORARY DEBUGGING HELPER - Bug 1806896
#
# Delete this file (and the fdbg() calls that reference it) once the
# flag_activity hang has been diagnosed.
#
# Every line it emits is a single-line INFO record prefixed with FLAGDBG,
# so it can be pulled out of the GCP log console with:
#
#   jsonPayload.Fields.msg:"FLAGDBG"
#
# Optional stack sampler for the hang itself: set BMO_FLAGDBG_WATCHDOG to a
# number of seconds in the app container's environment. While the flag code
# is running, a SIGALRM stack trace is logged every N seconds, so the last
# sample before the request times out shows exactly where it is stuck.

package Bugzilla::FlagDebug;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;

use Time::HiRes ();

use base qw(Exporter);

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw(fdbg fdbg_watchdog_on fdbg_watchdog_off);
## use critic

use constant MAX_WATCHDOG_SAMPLES => 10;

sub _elapsed_ms {
  my $cache = eval { Bugzilla->request_cache } or return -1;
  my $t0 = $cache->{flagdebug_t0} //= Time::HiRes::time();
  return sprintf '%.1f', (Time::HiRes::time() - $t0) * 1000;
}

# Transaction nesting depth as tracked by Bugzilla::DB. A depth that keeps
# climbing, or never returns to 0, is the thing to look for here.
sub _txn_depth {
  my $dbh = eval { Bugzilla->dbh } or return 'nodbh';
  return $dbh->{private_bz_transaction_count} // 0;
}

sub fdbg {
  my ($label, %fields) = @_;

  my @pairs;
  foreach my $key (sort keys %fields) {
    my $value = defined $fields{$key} ? $fields{$key} : 'undef';
    push @pairs, "$key=$value";
  }

  my $detail  = join q{ }, @pairs;
  my $message = 'FLAGDBG '
    . $label
    . ' at='
    . _elapsed_ms()
    . 'ms txn_depth='
    . _txn_depth() . q{ }
    . $detail;

  INFO($message);

  return;
}

sub fdbg_watchdog_on {
  my ($label) = @_;

  my $secs = $ENV{BMO_FLAGDBG_WATCHDOG} or return;
  my $samples = 0;

  $SIG{ALRM} = sub {
    require Carp;
    my $trace = Carp::longmess('still running');
    $trace =~ s/\s*\n\s*/ | /g;
    $samples++;
    INFO('FLAGDBG WATCHDOG '
        . $label
        . ' sample='
        . $samples
        . ' at='
        . _elapsed_ms()
        . 'ms txn_depth='
        . _txn_depth()
        . ' stack='
        . $trace);

    # Keep sampling so we can see whether it is stuck in one place or
    # spinning through a loop.
    alarm $secs if $samples < MAX_WATCHDOG_SAMPLES;
  };

  alarm $secs;
  return;
}

sub fdbg_watchdog_off {
  return unless $ENV{BMO_FLAGDBG_WATCHDOG};
  alarm 0;
  return;
}

1;
