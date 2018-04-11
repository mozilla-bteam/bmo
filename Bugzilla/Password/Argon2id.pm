# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Password::Argon2id;
use 5.10.1;
use Moo;

use Crypt::Argon2 qw(argon2id_pass argon2id_verify);

with 'Bugzilla::Password';

has 'password' => (
    is       => 'ro',
    required => 1,
);

has 'salt' => (
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

    return argon2id_verify("$other", $self->password);
}

sub _build_salt {
    return Bugzilla::Util::generate_random_password(16);
}

sub _build_encoded_password {
    my ($self) = @_;

    return argon2id_pass($self->password, $self->salt, 3, '32M', 1, 16);
}

1;