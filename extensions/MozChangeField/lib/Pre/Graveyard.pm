# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Pre::Graveyard;

use 5.10.1;
use Moo;

use Bugzilla::Constants;

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug      = $args->{'bug'};
  my $editbugs = $args->{'editbugs'};

  # Bugs in the Graveyard classification require editbugs to make any change.
  if (
    $bug->id
    && !$editbugs
    && $bug->product_obj->classification->name eq 'Graveyard'
  ) {
    # Bugs in the 'Invalid Bugs' product _are_ allowed to be edited by the
    # reporter.  This allows them to move the bug should it be incorrectly
    # classified as invalid.
    # This carve-out also allows bugs to be created in the 'Invalid Bugs'
    # product by anyone.
    my $field = $args->{'field'};
    if (
      $bug->reporter->id == Bugzilla->user->id
      && $bug->product_obj->name eq 'Invalid Bugs'
    ) {
      return undef;
    }

    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You require "editbugs" permission to modify archived bugs.',
    };
  }
  return undef;
}

1;
