# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::S3;

use 5.10.1;
use Moo;

use Bugzilla::Error;
use Bugzilla::S3;

has 's3'         => (is => 'lazy');
has 'bucket'     => (is => 'lazy');
has 'is_enabled' => (is => 'lazy');

sub _build_s3 {
  my $self = shift;
  $self->{s3} ||= Bugzilla::S3->new({
    aws_access_key_id     => Bugzilla->params->{s3_mining_access_key_id},
    aws_secret_access_key => Bugzilla->params->{s3_mining_secret_access_key},
    secure                => 1,
    retry                 => 1,
  });
  return $self->{s3};
}

sub _build_bucket {
  my $self = shift;
  $self->{bucket} ||= $self->s3->bucket(Bugzilla->params->{s3_mining_bucket});
  return $self->bucket;
}

sub _build_is_enabled {
  my $params = Bugzilla->params;
  return !($params->{s3_mining_access_key_id}
    && $params->{s3_mining_secret_access_key}
    && $params->{s3_mining_bucket}) ? 0 : 1;
}

sub set_data {
  my ($self, $product, $data) = @_;
  unless ($self->bucket->add_key($product, $data)) {
    warn "Failed to add data for product $product to S3: "
      . $self->bucket->errstr . "\n";
    ThrowCodeError('s3_mining_add_failed',
      {product => $product, reason => $self->bucket->errstr});
  }
  return $self;
}

sub get_data {
  my ($self, $product) = @_;
  my $response = $self->bucket->get_key($product);
  if (!$response) {
    warn "Failed to retrieve data for product $product from S3: "
      . $self->bucket->errstr . "\n";
    ThrowCodeError('s3_mining_get_failed',
      {product => $product, reason => $self->bucket->errstr});
  }
  return $response->{value};
}

sub remove_data {
  my ($self, $product) = @_;
  $self->bucket->delete_key($product)
    or warn "Failed to remove data for product $product from S3: "
    . $self->bucket->errstr . "\n";
  return $self;
}

sub data_exists {
  my ($self, $product) = @_;
  return !!$self->bucket->head_key($product);
}

1;
