# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::ChangeSet;

use 5.10.1;
use strict;
use warnings;
use Moo;
use MooX::StrictConstructor;
use Types::Standard qw(Bool Str ArrayRef HashRef);
use Type::Utils;

use Bugzilla::ChangeSet::Change;
use Bugzilla::ChangeSet::Update;
use Bugzilla::ChangeSet::Create;
use List::MoreUtils qw(all);

my $Change = role_type { role => 'Bugzilla::ChangeSet::Change' };
my $Code   = declare as Str, where { ref eval("sub { $_ }") } message { "should be perl code as Str!" };

has 'user'       => (is => 'ro', isa => HashRef);
has 'changes'    => (is => 'lazy', isa => ArrayRef[$Change]);
has 'references'    => (is => 'lazy', isa => ArrayRef);
has 'before_run' => (is => 'ro', isa => Str);
has 'after_update' => ( is => 'ro', isa => HashRef );

sub save {
    my ($self, $file) = @_;
    open my $fh, '>:bytes', $file or die "unable to write file: $!";
    print $fh JSON::XS->new->pretty->canonical->convert_blessed->encode($self);
    close $fh;
}

sub load {
    my ($class, $file) = @_;
    my $json = JSON::XS->new->filter_json_single_key_object(
        '$PERL' => sub {
            my $val = $_[0];
            return $val->{__TYPE__}->new($val->{__ARGS__});
        }
    );
    open my $fh, '<:bytes', $file or die "unable to read file: $!";
    my $s = do {
        local $/ = undef;
        <$fh>;
    };
    close $fh;
    $json->decode($s);
}

sub summarize {
    my ($self) = @_;
    $self->validate_references;
    $self->validate_changes;

    say "changes to be made by ", $self->user->{name};

    foreach my $change (@{$self->changes}) {
        say $change->summary;
    }
}

sub apply {
    my ($self) = @_;
    $self->validate_references;
    $self->validate_changes;
}

sub validate_references {
    my ($self) = @_;

    unless (all { $_->is_valid } @{ $self->references }) {
        die "Invalid references!";
    }
}

sub validate_changes {
    my ($self) = @_;

    foreach my $change (@{ $self->changes }) {
        unless ($change->is_valid) {
            die "Invalid change:\n", $change->summary;
        }
    }
}

sub new_reference {
    my ($self, $obj) = @_;
    my $reference = Bugzilla::ChangeSet::Reference->new(class => ref $obj, id => $obj->id);
    push @{ $self->references }, $reference;
    return $reference;
}

sub new_update {
    my ($self, %init) = @_;
    my $update = Bugzilla::ChangeSet::Update->new(%init);
    push @{ $self->changes }, $update;
    return $update;
}

sub new_create {
    my ($self, %init) = @_;
    my $create = Bugzilla::ChangeSet::Create->new(%init);
    push @{ $self->{changes} }, $create;
    return $create;
}

sub TO_JSON {
    my ($self) = @_;

    return {
        '$PERL' => {
            __TYPE__ => __PACKAGE__,
            __ARGS__ => {
                user => $self->user,
                before_run   => $self->before_run,
                after_update => $self->after_update,
                references => $self->references,
                changes => [
                    grep { $_->is_dirty } @{ $self->changes }
                ],
            },
        }
    };
}


sub _build_references { [] }
sub _build_changes { [] }

1;
