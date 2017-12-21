# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::ChangeSet::Reference;

use 5.10.1;
use strict;
use warnings;
use Moo;
use MooX::StrictConstructor;
use Types::Standard qw(ClassName Int HashRef);
use Type::Utils;

has 'class'   => ( is => 'ro', required => 1, isa => ClassName );
has 'id'      => ( is => 'ro', required => 1, isa => Int );
has '_object' => ( is => 'lazy' );

sub _build__object {
    my ($self) = @_;
    return $self->class->new({id => $self->id, cache => 1 });
}

sub get {
    my ($self, $field) = @_;
    return $self->_object->$field;
}

sub is_valid {
    my ($self) = @_;

    return $self->_object && $self->_object->isa($self->class) && $self->_object->id == $self->id;
}

sub TO_JSON {
    my ($self) = @_;
    return {
        '$PERL' => {
            __TYPE__ => __PACKAGE__,
            __ARGS__ => {
                class => $self->class,
                id    => $self->id,
            }
        },
    };
}

1;
