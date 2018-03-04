# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::PSGI;
use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);

use Bugzilla::Logging;
our @EXPORT_OK = qw(compile_cgi);

sub compile_cgi {
    my ($script) = @_;
    require CGI::Compile;
    require CGI::Emulate::PSGI;

    my $cgi = CGI::Compile->compile($script);
    my $app = CGI::Emulate::PSGI->handler(
        sub {
            Bugzilla::init_page();
            $cgi->();
        }
    );
    return sub {
        my $env = shift;
        if ($env->{'psgix.cleanup'}) {
            push @{ $env->{'psgix.cleanup.handler'} }, \&Bugzilla::_cleanup;
        }
        my $res = $app->($env);
        Bugzilla::_cleanup() if not $env->{'psgix.cleanup'};
        return $res;
    };
}


1;