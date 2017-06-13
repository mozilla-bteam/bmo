# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::ChangeSet::Create;

use 5.10.1;
use strict;
use warnings;
use Moo;
use MooX::StrictConstructor;
use Types::Standard qw(Str HashRef);
use Type::Utils;

with 'Bugzilla::ChangeSet::Change';

has 'args' => ( is => 'ro', required => 1, isa => HashRef );
has 'resolved_args' => ( is => 'lazy' );

sub is_dirty { 1 }

sub summary {
    my ($self) = @_;
    return "create " . $self->class . " (" . $self->args->{$self->class->NAME_FIELD} . ")";
}

sub is_valid {
    my ($self) = @_;
    my $class = $self->class;
    my $name = $self->resolved_args->{name};

    # Can't be valid without the natural key.
    return 0 unless $name;

    # Can't be valid if $name is already in the DB'
    return 0 if $class->new($self->resolved_args);

    return 1;
}

sub _build_resolved_args {
    my ($self) = @_;
    my $args = $self->args;
    my $NAME_FIELD = $self->class->NAME_FIELD;
    return {
        map {
            my $value = ref( $args->{$_} ) eq 'Bugzilla::ChangeSet::Reference'
                ? $args->{$_}->_object
                : $args->{$_};
            my $key = $_ eq $NAME_FIELD ? 'name' : $_;
            $key => $value
        } keys %$args
    };
}

sub TO_JSON {
    my ($self) = @_;
    return {
        '$PERL' => {
            __TYPE__ => __PACKAGE__,
            __ARGS__ => {
                class    => $self->class,
                args     => $self->args,
            },
        },
    };
}

1;
