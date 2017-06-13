#!/usr/bin/perl
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
use Bugzilla::Bug;
use Bugzilla::ChangeSet;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Search;
use List::MoreUtils qw(all);
use Getopt::Long;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
Bugzilla->error_mode(ERROR_MODE_DIE);
$SIG{__DIE__} = undef;

my ($apply);
GetOptions( 'apply' => \$apply );
my $change_set_file = shift @ARGV;

die "change-set is required!\n" unless $change_set_file;

my $cs = Bugzilla::ChangeSet->load($change_set_file);

if ($apply) {
    $cs->apply;
}
else {
    $cs->summarize;
}

