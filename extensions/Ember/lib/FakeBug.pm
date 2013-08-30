# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Ember::FakeBug;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;

our $AUTOLOAD;

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    return exists $self->{$name} ? $self->{$name} : undef;
}

sub check_can_change_field {
    my $self = shift;
    return Bugzilla::Bug::check_can_change_field($self, @_)
}

1;

