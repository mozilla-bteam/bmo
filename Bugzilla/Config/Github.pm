# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Github;

use 5.10.1;
use strict;
use warnings;

sub get_param_list {
  my $class      = shift;
  my @param_list = (
    {name => 'github_pr_linking_enabled',  type => 'b', default => 0},
    {name => 'github_pr_signature_secret', type => 't', default => ''},
    {name => 'github_push_comment_enabled', type => 'b', default => 0},
  );
  return @param_list;
}

1;
