# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Logger;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Extension::PhabBugz::Constants;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    return $self;
}

sub info  { shift->_log_it('INFO', @_) }
sub error { shift->_log_it('ERROR', @_) }
sub debug { shift->_log_it('DEBUG', @_) }

sub debugging {
    my ($self) = @_;
    return $self->{debug};
}

sub _log_it {
    require Apache2::Log;
    my ($self, $method, $message) = @_;
    return if $method eq 'DEBUG' && !$self->debugging;
    chomp $message;
    if ($ENV{MOD_PERL}) {
        Apache2::ServerRec::warn("Push $method: $message");
    } elsif ($ENV{SCRIPT_FILENAME}) {
        print STDERR "Push $method: $message\n";
    } else {
        print STDERR '[' . localtime(time) ."] $method: $message\n";
    }
}

1;
