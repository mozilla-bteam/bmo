# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::ConnectMozOrg;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

###############################
####        Methods        ####
###############################

sub should_handle {
  my ($class, $uri) = @_;
  return (lc($uri->authority) eq 'connect.mozilla.org'
      and $uri->path =~ /^\/t5\/(ideas|discussions)\//) ? 1 : 0;
}

sub _check_value {
  my ($class, $uri) = @_;
  $uri = $class->SUPER::_check_value($uri);
  return $uri;
}

1;
