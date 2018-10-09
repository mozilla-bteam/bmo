# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON;
use 5.10.1;
use Moo;

use Bugzilla::WebService::JSON::Lazy;
use JSON::MaybeXS;
use Scalar::Util qw(refaddr blessed);

use constant LazyJSON => 'Bugzilla::WebService::JSON::Lazy';

# this cache is used to lookup if something already has a lazy wrapper,
# using the address of the value.
has 'cache' => (is => 'lazy', clearer => 'clear_cache',);

# delegation all the json options to the real json encoder.
has 'json' => (
  is      => 'lazy',
  handles => [
    qw[utf8 ascii pretty canonical allow_nonref allow_blessed convert_blessed]
  ]
);

sub encode {
  my ($self, $val) = @_;
  if (blessed $val && $val->isa(LazyJSON)) {
    return $val;
  }
  else {
    my $cache = $self->cache;
    my $addr  = refaddr $val;

    # the Lazy class needs a reference to the real encoder for TO_JSON and stringification.
    $cache->{$addr} //= LazyJSON->new(value => $val, json => $self->json);
    return $cache->{$addr};
  }
}

sub decode {
  my ($self, $val) = @_;
  if (blessed $val && $val->isa(LazyJSON)) {
    return $val->value;
  }
  else {
    my $new_val = $self->json->decode($val);
    my $cache   = $self->cache;
    $cache->{refaddr $new_val } = Bugzilla::WebService::JSON::Lazy->new(
      value => $new_val,
      json  => $self->json
    );
    return $new_val;
  }
}

sub _build_json  { JSON::MaybeXS->new }
sub _build_cache { {} }

1;
