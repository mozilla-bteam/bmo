# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::Net;

use 5.10.1;
use Moo;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Net::S3;
use Bugzilla::Net::Google;

use Types::Standard qw(Int Str);

with 'Bugzilla::Attachment::Storage::Base';

has name     => (is => 'ro', required => 1, isa => Str,);
has datasize => (is => 'ro', required => 1, isa => Int,);
has driver   => (is => 'lazy');

sub _build_driver {
  my ($self) = @_;
  my $params = Bugzilla->params;

  my $driver;
  if ($self->name eq 's3') {
    $driver = Bugzilla::Net::S3->new({
      client_id  => $params->{aws_access_key_id},
      secret_key => $params->{aws_secret_access_key},
      bucket     => $params->{s3_bucket},
      host       => $params->{aws_host},
    });
  }
  elsif ($self->name eq 'google') {
    $driver = Bugzilla::Net::Google->new({
      bucket          => $params->{google_storage_bucket},
      host            => $params->{google_storage_host},
      service_account => $params->{google_storage_service_account},
    });
  }

  return $driver;
}

sub data_type {
  my ($self) = @_;
  return $self->driver->data_type;
}

sub set_data {
  my ($self, $data) = @_;
  my $attach_id = $self->attach_id;

  # Store that attachment data in the database if below mininum size
  if (
    (
         $self->data_type eq 's3'
      && $self->datasize < Bugzilla->params->{attachment_s3_minsize}
    )
    || ( $self->data_type eq 'google'
      && $self->datasize < Bugzilla->params->{attachment_google_minsize})
    )
  {
    require Bugzilla::Attachment::Storage::Database;
    return Bugzilla::Attachment::Storage::Database->new(
      {attach_id => $self->attach_id})->set_data($data);
  }

  unless ($self->driver->add_key($attach_id, $data)) {
    warn "Failed to add attachment $attach_id to net storage: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_storage_add_failed',
      {key => $attach_id, reason => $self->driver->error_string});
  }

  return $self;
}

sub get_data {
  my ($self)    = @_;
  my $attach_id = $self->attach_id;
  my $data      = $self->driver->get_key($attach_id);
  if (!$data) {
    warn "Failed to retrieve attachment $attach_id from net storage: "
      . $self->driver->error_string . "\n";
    ThrowCodeError('net_storage_get_failed',
      {key => $attach_id, reason => $self->driver->error_string});
  }
  return $data;
}

sub remove_data {
  my ($self) = @_;
  my $attach_id = $self->attach_id;
  $self->driver->delete_key($attach_id)
    or warn "Failed to remove attachment $attach_id from net storage: "
    . $self->driver->error_string . "\n";
  return $self;
}

sub data_exists {
  my ($self) = @_;
  return !!$self->driver->head_key($self->attach_id);
}

1;
