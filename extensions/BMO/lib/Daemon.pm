# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Daemon;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Extension::BMO::ETL;
use Bugzilla::Extension::BMO::ETL::Export;
use Bugzilla::Logging;

use Carp qw(confess);
use Daemon::Generic;
use File::Basename;
use Mojo::Util qw(dumper);
use Pod::Usage;

sub start {
  newdaemon();
}

sub gd_preconfig {
  my $self    = shift;
  my $pidfile = $self->{gd_args}{pidfile};
  if (!$pidfile) {
    $pidfile = bz_locations()->{datadir} . '/' . $self->{gd_progname} . '.pid';
  }
  return (pidfile => $pidfile);
}

sub gd_getopt {
  my $self = shift;
  $self->SUPER::gd_getopt();
  if ($self->{gd_args}{progname}) {
    $self->{gd_progname} = $self->{gd_args}{progname};
  }
  else {
    $self->{gd_progname} = basename($0);
  }
  $self->{_original_zero} = $0;
  $0 = $self->{gd_progname};
}

sub gd_postconfig {
  my $self = shift;
  $0 = delete $self->{_original_zero};
}

sub gd_more_opt {
  my $self = shift;
  return (
    'pidfile=s'         => \$self->{gd_args}{pidfile},
    'n=s'               => \$self->{gd_args}{progname},
    't|test'            => \$self->{gd_args}->{test},
    'q|quiet'           => \$self->{gd_args}->{quiet},
    's|snapshot-date=s' => \$self->{gd_args}->{snapshot_date},
  );
}

sub gd_usage {
  pod2usage({-verbose => 0, -exitval => 'NOEXIT'});
  return 0;
}

sub gd_redirect_output {
  my $self = shift;
  my $filename = bz_locations()->{datadir} . '/' . $self->{gd_progname} . '.log';
  open STDERR, '>>', $filename or (print "could not open stderr: $!" && exit 1);
  close STDOUT;
  open STDOUT, '>&', STDERR or die "redirect STDOUT -> STDERR: $!";
  $SIG{HUP} = sub {
    close STDERR;
    open STDERR, '>>', $filename or (print "could not open stderr: $!" && exit 1);
  };
}

sub gd_setup_signals {
  my $self = shift;
  $self->SUPER::gd_setup_signals();
  $SIG{TERM} = sub { $self->gd_quit_event(); }
}

sub gd_other_cmd {
  my ($self) = shift;
  if ($ARGV[0] eq 'once') {
    try {
      my $export = Bugzilla::Extension::BMO::ETL::Export->new(
        debug         => $self->{debug},
        test          => $self->{gd_args}->{test},
        quiet         => $self->{gd_args}->{quiet},
        snapshot_date => $self->{gd_args}->{snapshot_date},
      );
      $export->run_export;
      exit 0;
    }
    catch {
      FATAL($_);
    }
    finally {
      try {
        Bugzilla->_cleanup();
      }
      catch {
        FATAL("Error in _cleanup: $_");
        exit 1;
      }
    };
  }
  $self->SUPER::gd_other_cmd();
}

sub gd_run {
  my $self = shift;
  $::SIG{__DIE__} = \&Carp::confess if $self->{debug};
  my $etl = Bugzilla::Extension::BMO::ETL->new;
  $etl->is_daemon(1);
  $etl->start(
    debug         => $self->{debug},
    test          => $self->{gd_args}->{test},
    quiet         => $self->{gd_args}->{quiet},
    snapshot_date => $self->{gd_args}->{snapshot_date},
  );
}

sub gd_check {
  return 'OK';
}

1;
