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

use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs(dirname(__FILE__));
    lib->import($dir, File::Spec->catdir($dir, 'lib'), File::Spec->catdir($dir, qw(local lib perl5)));
    chdir $dir or die "chdir $dir failed: $!";
}

use Bugzilla::JobQueue::Worker;
use Bugzilla::JobQueue;
use Bugzilla;
use English qw(-no_match_vars $PROGRAM_NAME);
use File::Basename qw(basename);
use Getopt::Long qw(:config gnu_getopt);

BEGIN { Bugzilla->extensions };
my $name = basename(__FILE__);

GetOptions( 'name=s' => \$name );

if ($name) {
    ## no critic (Variables::RequireLocalizedPunctuationVars)
    $PROGRAM_NAME = $name;
}
Bugzilla::JobQueue::Worker->run('work');