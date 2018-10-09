# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON::Lazy;
use 5.10.1;
use Moo;

use overload q{""} => 'TO_STRING', fallback => 1;

# the JSON encoder. This should be the real one, not Bugzilla::WebService::JSON.
has 'json' => (is => 'ro', required => 1);

# this is the value that might eventually get passed to the encoder.
has 'value' => (is => 'ro');

sub TO_JSON {
  my ($self) = @_;

  return $self->value;
}

sub TO_STRING {
  my ($self) = @_;

  return $self->json->encode( $self->value );
}

1;
