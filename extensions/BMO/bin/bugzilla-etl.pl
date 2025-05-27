#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;

use lib qw(. lib local/lib/perl5);

BEGIN {
  use Bugzilla;
  Bugzilla->extensions;
}

use Bugzilla::Extension::BMO::Daemon;
Bugzilla::Extension::BMO::Daemon->start();

=head1 NAME

bugzilla-etl.pl - Export a daily snapshot of the BMO database to BigQuery.

=head1 SYNOPSIS

  bugzilla-etl.pl [OPTIONS] COMMAND

    OPTIONS:
      -f         Run in the foreground (don't detach)
      -d         Output a lot of debugging information
      -p file    Specify the file where bugzilla-etl.pl should store its current
                 process id. Defaults to F<data/bugzilla-etl.pid>.
      --snapshot <date> Use the provided snapshot date instead of current date.
      --test     Output the JSON to test files instead of sending to BigQuery.
      --quiet    Do not output any information while running.

    COMMANDS:
      start     Starts a new bugzilla-etl daemon if there isn't one running already
      stop      Stops a running bugzilla-etl daemon
      restart   Stops a running bugzilla-etl if one is running, and then
                starts a new one.
      once      Execute only once and then exit.
      check     Report the current status of the daemon.
      help      Display this usage info
