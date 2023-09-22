# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

sub install_update_db {
  my $dbh = Bugzilla->dbh;
  $dbh->bz_drop_table('profiles_iam');
  $dbh->bz_drop_table('mozilla_iam_updates');
}

__PACKAGE__->NAME;
