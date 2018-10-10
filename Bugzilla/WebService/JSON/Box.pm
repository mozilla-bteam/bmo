# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON::Box;
use 5.10.1;
use Moo;
use Type::Utils;

# this is the value that might eventually get passed to the encoder.
has 'value' => (is => 'ro');

has 'json' => (
  is       => 'ro',
  isa      => class_type({class => 'Bugzilla::WebService::JSON'}),
  weak_ref => 1,
  required => 1,
);

has 'json_value' => ( is => 'lazy' );

sub TO_JSON {
  my ($self) = @_;

  return $self->value;
}

sub _build_json_value {
  my ($self) = @_;
  my $str = $self->json->_encode( $self->value );
  utf8::encode($str) unless utf8::downgrade($str, 1);
  return $str;
}

1;
