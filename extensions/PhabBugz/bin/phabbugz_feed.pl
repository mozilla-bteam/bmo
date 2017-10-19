#!/usr/bin/perl

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

use Bugzilla::Extension::PhabBugz::Daemon;
Bugzilla::Extension::PhabBugz::Daemon->start();

=head1 NAME

phabbugzd.pl - Query Phabricator for interesting changes and update bugs related to revisions.

=head1 SYNOPSIS

  phabbugzd.pl [OPTIONS] COMMAND

    OPTIONS:
      -f        Run in the foreground (don't detach)
      -d        Output a lot of debugging information
      -p file   Specify the file where phabbugzd.pl should store its current
                process id. Defaults to F<data/phabbugzd.pl.pid>.
      -n name   What should this process call itself in the system log?
                Defaults to the full path you used to invoke the script.

    COMMANDS:
      start     Starts a new phabbugzd daemon if there isn't one running already
      stop      Stops a running phabbugzd daemon
      restart   Stops a running phabbugzd if one is running, and then
                starts a new one.
      check     Report the current status of the daemon.
      install   On some *nix systems, this automatically installs and
                configures phabbugzd.pl as a system service so that it will
                start every time the machine boots.
      uninstall Removes the system service for phabbugzd.pl.
      help      Display this usage info