# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::JSON;
use 5.10.1;
use Moo;

use Bugzilla::WebService::JSON::Box;
use JSON::MaybeXS;
use Scalar::Util qw(refaddr blessed);
use Package::Stash;

use constant Box => 'Bugzilla::WebService::JSON::Box';

# this cache is used to lookup if something already has a lazy wrapper,
# using the address of the value.
has 'cache' => (is => 'lazy', clearer => 'clear_cache',);

has 'json' =>
  (is => 'lazy', handles => {_encode => 'encode', _decode => 'decode'},);

# delegation all the json options to the real json encoder.
my @json_methods = qw(
  utf8 ascii pretty canonical
  allow_nonref allow_blessed convert_blessed
);
my $stash = Package::Stash->new(__PACKAGE__);
foreach my $method (@json_methods) {
  my $symbol = '&' . $method;
  $stash->add_symbol(
    $symbol => sub {
      my $self = shift;
      $self->json->$method(@_);
      return $self;
    }
  );
}

sub is_retained {
  my ($self, $val) = @_;
  my $addr = refaddr $val;
  return $addr && $self->cache->{$addr};
}

sub retain {
  my ($self, $val) = @_;

  if (blessed $val && $val->isa(Box)) {
    return $self->cache->{refaddr $val->value} //= $val;
  }
  else {
    return $self->retain(Box->new(json => $self, value => $val));
  }
}

sub encode {
  my ($self, $val) = @_;
  my $id = refaddr $val;
  my $box = $id && $self->cache->{$id};
  return $box if $box;
  return $self->retain($val);
}

sub decode {
  my ($self, $val) = @_;

  if (blessed $val && $val->isa(Box)) {
    return $val->value;
  }
  else {
    return $self->retain($self->_decode($val))->value;
  }
}

sub _build_json  { JSON::MaybeXS->new }
sub _build_cache { {} }

1;
