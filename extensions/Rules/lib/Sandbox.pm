# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Sandbox;

use 5.10.1;
use strict;
use warnings;
use Bugzilla::Constants;

our ($BUG, $FIELD, $PRIV_RESULTS);

sub field {
  my ($field) = @_;
  return lc($FIELD) eq lc($field);
}

sub group {
  my ($group_name) = @_;
  return Bugzilla->user->in_group($group_name);
}

sub product {
  my ($product_name) = @_;
  return lc($BUG->product) eq lc($product_name);
}

sub deny {
  push(@$PRIV_RESULTS, PRIVILEGES_REQUIRED_EMPOWERED);
}

1;
