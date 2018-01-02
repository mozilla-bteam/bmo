# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl::ResponseHandler;
use 5.10.1;
use strict;
use warnings;
use base qw(ModPerl::Registry);

use Bugzilla::Constants qw(USAGE_MODE_REST USE_NYTPROF);
use Time::HiRes;

sub handler {
    my $class = shift;

    # $0 is broken under mod_perl before 2.0.2, so we have to set it
    # here explicitly or init_page's shutdownhtml code won't work right.
    $0 = $ENV{'SCRIPT_FILENAME'};

    # Prevent "use lib" from modifying @INC in the case where a .cgi file
    # is being automatically recompiled by mod_perl when Apache is
    # running. (This happens if a file changes while Apache is already
    # running.)
    no warnings 'redefine';
    local *lib::import = sub {};
    use warnings;


    if (USE_NYTPROF) {
        state $count = {};
        my $script = File::Basename::basename($ENV{SCRIPT_FILENAME});
        $script =~ s/\.cgi$//;
        my $file = bz_locations()->{datadir} . "/nytprof.$script." . ++$count->{$$};
        DB::enable_profile($file);
    }
    Bugzilla::init_page();
    my $start = Time::HiRes::time();
    my $result = $class->SUPER::handler(@_);
    warn "[request_time] ", Bugzilla->cgi->request_uri, " took ", Time::HiRes::time() - $start, " seconds to execute";
    if (USE_NYTPROF) {
        DB::disable_profile();
        DB::finish_profile();
    }

    # When returning data from the REST api we must only return 200 or 304,
    # which tells Apache not to append its error html documents to the
    # response.
    return Bugzilla->usage_mode == USAGE_MODE_REST && $result != 304
        ? Apache2::Const::OK
        : $result;
}

1;
