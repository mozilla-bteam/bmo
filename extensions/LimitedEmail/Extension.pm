# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::LimitedEmail;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

our $VERSION = '2';

use FileHandle;
use Date::Format;
use Encode qw(encode_utf8);
use Bugzilla::Constants qw(bz_locations);

sub mailer_before_send {
  my ($self, $args) = @_;
  my $email  = $args->{email};
  my $header = $email->{header};
  return if $header->header('to') eq '';

  my $blocked = '';
  if (!deliver_to($header->header('to'))) {
    $blocked = $header->header('to');
    $header->header_set(to => '');
  }

  my $log_filename = bz_locations->{'datadir'} . '/mail.log';
  my $fh           = FileHandle->new(">>$log_filename");
  if ($fh) {
    print $fh encode_utf8(sprintf(
      "[%s] %s%s %s : %s\n",
      time2str('%D %T', time),
      ($blocked eq '' ? '' : '(blocked) '),
      ($blocked eq '' ? $header->header('to') : $blocked),
      $header->header('X-Bugzilla-Reason') || '-',
      $header->header('subject')
    ));
    $fh->close();
  }
}

sub deliver_to {
  my $email      = address_of(shift);
  my $ra_filters = Bugzilla::Extension::LimitedEmail::FILTERS;
  foreach my $re (@$ra_filters) {
    if ($email =~ $re) {
      return 1;
    }
  }
  return 0;
}

sub address_of {
  my $email = shift;
  return $email =~ /<([^>]+)>/ ? $1 : $email;
}

__PACKAGE__->NAME;
