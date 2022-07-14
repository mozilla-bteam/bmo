# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::External;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

use Bugzilla::Constants;
use Bugzilla::Error;

###############################
####        Methods        ####
###############################

sub should_handle {
  my ($class, $uri) = @_;

  # We will handle this if it is an external URI and not the
  # same hostname as this Bugzilla instance
  my $canonical_local = URI->new($class->local_uri)->canonical;
  if (($uri->scheme eq 'http' || $uri->scheme eq 'https')
    && $uri->canonical->authority ne $canonical_local->authority)
  {
    return 1;
  }
  return 0;
}

sub _check_value {
  my ($class, $uri) = @_;

  $uri = $class->SUPER::_check_value($uri);

  if ($uri->scheme ne 'http' && $uri->scheme ne 'https') {
    ThrowUserError('bug_url_invalid', {url => $uri->as_string, reason => 'http'});
  }

  if (!$uri->authority) {
    ThrowUserError('bug_url_invalid', {url => $uri->as_string, reason => 'http'});
  }

  if (length($uri->path) > MAX_BUG_URL_LENGTH) {
    ThrowUserError('bug_url_too_long', {url => $uri->path});
  }

  # always https
  $uri->scheme('https');

  return $uri;
}

1;
