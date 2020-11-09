# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Resources::Bugzilla;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Keyword;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::Util ();

use Bugzilla::Extension::BzAPI::Constants;

use Digest::MD5 qw(md5_base64);

#########################
# REST Resource Methods #
#########################

BEGIN {
  require Bugzilla::WebService::Bugzilla;
  *Bugzilla::WebService::Bugzilla::get_empty = \&get_empty;
}

sub rest_handlers {
  my $rest_handlers = [qr{^/$}, {GET => {resource => {method => 'get_empty'}}},];
  return $rest_handlers;
}

sub get_empty {
  my ($self) = @_;
  return {
    ref => $self->type('string', Bugzilla->localconfig->urlbase . "bzapi/"),
    documentation => $self->type('string', BZAPI_DOC),
    version       => $self->type('string', BUGZILLA_VERSION)
  };
}

1;
