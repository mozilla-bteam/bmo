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

BEGIN {
  use Bugzilla;
  Bugzilla->extensions;
}

use Bugzilla::Extension::MozillaIAM::Daemon;
Bugzilla::Extension::MozillaIAM::Daemon->start();

=head1 NAME

person_update.pl - Query MozillaIAM for interesting changes to Mozilla tracked accounts.

=head1 SYNOPSIS

  person_update.pl [OPTIONS] COMMAND

    OPTIONS:
      -f        Run in the foreground (don't detach)
      -d        Output a lot of debugging information
      -p file   Specify the file where person_update.pl should store its current
                process id. Defaults to F<data/person_update.pl.pid>.
      -n name   What should this process call itself in the system log?
                Defaults to the full path you used to invoke the script.

    COMMANDS:
      start     Starts a new person_update daemon if there isn't one running already
      stop      Stops a running person_update daemon
      restart   Stops a running person_update if one is running, and then
                starts a new one.
      check     Report the current status of the daemon.
      install   On some *nix systems, this automatically installs and
                configures person_update.pl as a system service so that it will
                start every time the machine boots.
      uninstall Removes the system service for person_update.pl.
      help      Display this usage info
