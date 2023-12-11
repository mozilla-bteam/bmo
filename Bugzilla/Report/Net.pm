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
use Bugzilla::Net::S3;

has driver     => (is => 'lazy');
has is_enabled => (is => 'lazy');

sub _build_driver {
  my $self = shift;

  my $driver = Bugzilla::Net::S3->new({
    client_id  => Bugzilla->params->{s3_mining_access_key_id},
    secret_key => Bugzilla->params->{s3_mining_secret_access_key},
    bucket     => Bugzilla->params->{s3_mining_bucket},
    host       => Bugzilla->params->{aws_host},
    secure     => 1,
    retry      => 1,
  });

  return $driver;
}

sub _build_is_enabled {
  return Bugzilla->params->{s3_mining_enabled} ? 1 : 0;
}

sub set_data {
  my ($self, $product, $data) = @_;
  unless ($self->driver->add_key($product, $data)) {
    warn "Failed to add data for product $product to S3: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_mining_add_failed',
      {product => $product, reason => $self->driver->error_string});
  }
  return $self;
}

sub get_data {
  my ($self, $product) = @_;
  my $response = $self->driver->get_key($product);
  if (!$response) {
    warn "Failed to retrieve data for product $product from S3: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_mining_get_failed',
      {product => $product, reason => $self->driver->error_string});
  }
  use Bugzilla::Logging;
  use Mojo::Util qw(dumper);
  INFO(dumper $response);
  return $response->{value};
}

sub remove_data {
  my ($self, $product) = @_;
  $self->driver->delete_key($product)
    or warn "Failed to remove data for product $product from S3: "
    . $self->driver->error_string . "\n";
  return $self;
}

sub data_exists {
  my ($self, $product) = @_;
  return !!$self->driver->head_key($product);
}

1;
