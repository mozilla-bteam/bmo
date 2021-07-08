# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM::Constants;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
  CIS_UPDATE_SECONDS
  MANUAL_UPDATE_SECONDS
  POLL_TIMEOUT
);

use constant CIS_UPDATE_SECONDS    => $ENV{CIS_UPDATE_SECONDS}    // 10;
use constant MANUAL_UPDATE_SECONDS => $ENV{MANUAL_UPDATE_SECONDS} // 3600;
use constant POLL_TIMEOUT          => $ENV{POLL_TIMEOUT}          // 3600;

1;
