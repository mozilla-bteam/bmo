# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Password;
use 5.10.1;
use Moo::Role;

use overload (
    q{eq} => 'equals',
    q{ne} => 'not_equals',
    q{==} => 'equals',
    q{!=} => 'not_equals',
    q{""} => 'to_string',
    bool => sub { 1 },
    fallback => 1,
);

requires 'to_string', 'equals';

sub not_equals {
    my ($self, $other) = @_;

    return not $self->equals($other);
}

1;