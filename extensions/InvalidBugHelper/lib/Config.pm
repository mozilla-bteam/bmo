# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::InvalidBugHelper::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 512;

sub get_param_list {
  return (
    {
      name    => 'invalidbughelper_warning_text',
      type    => 'l',
      default =>
        "This bug has been filed incorrectly as a test or spam submission and has "
        . "been moved to the Invalid Bugs product.\n\n"
        . "If you believe this was done in error, please contact "
        . "bugzilla-admin\@mozilla.org.",
    },
  );
}

1;
