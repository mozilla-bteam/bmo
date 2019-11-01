# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::S3;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::S3;

sub new {
  my $s3 = Bugzilla::S3->new({
    aws_access_key_id     => Bugzilla->params->{aws_access_key_id},
    aws_secret_access_key => Bugzilla->params->{aws_secret_access_key},
    secure                => 1,
  });
  return
    bless({s3 => $s3, bucket => $s3->bucket(Bugzilla->params->{s3_bucket}),},
    shift);
}

sub store {
  my ($self, $attachment, $data) = @_;

  if (_store_db_check($attachment)) {
    require Bugzilla::Attachment::Database;
    Bugzilla::Attachment::Database->new()->store($attachment, $data);
    return;
  }

  my $attach_id = $attachment->id;
  unless ($self->{bucket}->add_key($attach_id, $data)) {
    warn "Failed to add attachment $attach_id to S3: "
      . $self->{bucket}->errstr . "\n";
    ThrowCodeError('s3_add_failed',
      {attach_id => $attach_id, reason => $self->{bucket}->errstr});
  }
}

sub retrieve {
  my ($self, $attachment) = @_;

  if (_store_db_check($attachment)) {
    require Bugzilla::Attachment::Database;
    return Bugzilla::Attachment::Database->new()->retrieve($attachment);
  }

  my $attach_id = $attachment->id;
  my $response = $self->{bucket}->get_key($attach_id);
  if (!$response) {
    warn "Failed to retrieve attachment $attach_id from S3: "
      . $self->{bucket}->errstr . "\n";
    ThrowCodeError('s3_get_failed',
      {attach_id => $attach_id, reason => $self->{bucket}->errstr});
  }
  return $response->{value};
}

sub remove {
  my ($self, $attachment) = @_;

  if (_store_db_check($attachment)) {
    require Bugzilla::Attachment::Database;
    Bugzilla::Attachment::Database->new()->remove($attachment);
    return;
  }

  my $attach_id = $attachment->id;
  $self->{bucket}->delete_key($attach_id)
    or warn "Failed to remove attachment $attach_id from S3: "
    . $self->{bucket}->errstr . "\n";
}

sub exists {
  my ($self, $attachment) = @_;

  if (_store_db_check($attachment)) {
    require Bugzilla::Attachment::Database;
    return Bugzilla::Attachment::Database->new()->exists($attachment);
  }

  return !!$self->{bucket}->head_key($attachment->id);
}

# If the attachment is larger than attachment_s3_minsize,
# we instead store it in the database.
sub _store_db_check {
  my ($attachment) = @_;
  if (Bugzilla->params->{attachment_s3_minsize}
      && $attachment->datasize < Bugzilla->params->{attachment_s3_minsize})
  {
    return 1;
  }
  return 0;
}

1;
