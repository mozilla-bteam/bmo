# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Ideas;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::BugUrl);

use Bugzilla::Error;
use Bugzilla::Util;
use List::MoreUtils qw( any );

###############################
####        Methods        ####
###############################

# https://ideas.mozilla.org/post/718775
# https://mozilla.crowdicity.com/post/718775

sub should_handle {
  my ($class, $uri) = @_;
  return any { lc($uri->authority) eq $_ }
  qw( ideas.mozilla.org mozilla.crowdicity.com );
}

sub _check_value {
  my ($class, $uri) = @_;
  $uri = $class->SUPER::_check_value($uri);

  return $uri if $uri->path =~ m{^/post/\d+};

  ThrowUserError('bug_url_invalid', {url => "$uri"});
}

1;
