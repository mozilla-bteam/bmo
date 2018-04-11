# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Password::Digest;
use 5.10.1;
use Moo;
use Digest;

with 'Bugzilla::Password';

has 'password' => (
    is       => 'ro',
    required => 1,
);

has 'salt' => (
    is       => 'ro',
    required => 1,
);

has 'algorithm' => (
    is       => 'ro',
    required => 1,
);

has 'encoded_password' => (
    is => 'lazy',
);


sub to_string {
    my ($self) = @_;

    return $self->encoded_password;
}

sub equals {
    my ($self, $other) = @_;

    return $self->encoded_password eq "$other";
}

sub _build_encoded_password {
    my ($self) = @_;

    my $hasher = Digest->new($self->algorithm);
    $hasher->add($self->password, $self->salt);

    return sprintf '%s%s{%s}', $self->salt, $hasher->b64digest, $self->algorithm;
}

1;