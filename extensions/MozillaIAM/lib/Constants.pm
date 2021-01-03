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
  PERSON_POLL_SECONDS
  PERSON_TIMEOUT
);

use constant PERSON_POLL_SECONDS => $ENV{PERSON_POLL_SECONDS} // 30;
use constant PERSON_TIMEOUT      => $ENV{PERSON_TIMEOUT}      // 60;

1;
