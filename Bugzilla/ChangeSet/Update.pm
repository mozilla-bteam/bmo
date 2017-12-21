# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::ChangeSet::Update;

use 5.10.1;
use strict;
use warnings;
use Moo;
use MooX::StrictConstructor;
use Types::Standard qw(Bool Str ArrayRef ClassName Int);
use Type::Utils;

extends 'Bugzilla::ChangeSet::Reference';

has 'stash'   => ( is => 'lazy', predicate => 'is_dirty' );
with 'Bugzilla::ChangeSet::Change';

sub summary {
    my ($self) = @_;
    return "Update " . $self->class . " id = " . $self->id . "\n" . 
    join("\n",
        map {
            my ($old, $new) = @{ $self->stash->{$_} };
            sprintf "    %-20s :: %s => %s", $_, $old, $new
        } keys %{ $self->stash });
}

sub is_valid {
    my ($self) = @_;
    return 0 unless $self->is_dirty;
    foreach my $key (keys %{ $self->stash }) {
        my ($old, $new) = @{ $self->stash->{$key} };
        return 0 if $old eq $new;
        return 0 if $self->get($key) ne $old;
    }
    return 1;
}

sub set {
    my ($self, $field, $value) = @_;
    $self->stash->{ $field } = [ $self->get($field), $value ];
}

sub _build_stash {
    return {};
}

sub TO_JSON {
    my ($self) = @_;
    return {
        '$PERL' => {
            __TYPE__ => __PACKAGE__,
            __ARGS__ => {
                class    => $self->class,
                id       => $self->id,
                stash    => $self->stash,
            },
        },
    };
}

1;
