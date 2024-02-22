# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::Net;

use 5.10.1;
use Moo;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Net::Google;

has driver     => (is => 'lazy');
has is_enabled => (is => 'lazy');

sub _build_driver {
  my $self = shift;

  my $driver = Bugzilla::Net::Google->new({
    bucket          => Bugzilla->params->{mining_google_bucket},
    host            => Bugzilla->params->{mining_google_host},
    service_account => Bugzilla->params->{mining_google_service_account},
    secure          => 1,
    retry           => 1,
  });

  return $driver;
}

sub _build_is_enabled {
  return Bugzilla->params->{mining_enabled} ? 1 : 0;
}

sub set_data {
  my ($self, $product, $data) = @_;
  unless ($self->driver->add_key($product, $data)) {
    warn "Failed to add data for product $product to net storage: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_mining_add_failed',
      {product => $product, reason => $self->driver->error_string});
  }
  return $self;
}

sub get_data {
  my ($self, $product) = @_;
  my $data = $self->driver->get_key($product);
  if (!$data) {
    warn "Failed to retrieve data for product $product from net storage: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_mining_get_failed',
      {product => $product, reason => $self->driver->error_string});
  }
  return $data;
}

sub remove_data {
  my ($self, $product) = @_;
  $self->driver->delete_key($product)
    or warn "Failed to remove data for product $product from net storage: "
    . $self->driver->error_string . "\n";
  return $self;
}

sub data_exists {
  my ($self, $product) = @_;
  return !!$self->driver->head_key($product);
}

1;
