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

use Bugzilla;
use Bugzilla::Constants;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $sth = $dbh->prepare(
  q{SELECT blocked, dependson
        FROM dependencies
       WHERE blocked = ? OR dependson = ?}
);

my %seen  = ();
my @stack = (1733050);

foreach my $id (@stack) {
  my $dependencies = $dbh->selectall_arrayref($sth, undef, ($id, $id));

  foreach my $dependency (@{$dependencies}) {
    my ($blocked, $dependson) = @{$dependency};
    if ($blocked != $id && !exists $seen{$blocked}) {
      push @stack, $blocked;
    }
    if ($dependson != $id && !exists $seen{$dependson}) {
      push @stack, $dependson;
    }
    say "$dependson --> $blocked";
  }
}

