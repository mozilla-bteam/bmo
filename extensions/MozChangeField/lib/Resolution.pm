# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Resolution;

use 5.10.1;
use Moo;

use Bugzilla::Constants;

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $canconfirm   = $args->{'canconfirm'};
  my $editbugs     = $args->{'editbugs'};

  return undef if $field ne 'resolution';

  # Canconfirm is really "cantriage"; users with canconfirm can also mark
  # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
  if (
    $canconfirm
    && ( $new_value eq 'DUPLICATE'
      || $new_value eq 'WORKSFORME'
      || $new_value eq 'INCOMPLETE'
      || ($old_value eq '' && $new_value eq '1'))
    )
  {
    return {
      result => PRIVILEGES_REQUIRED_NONE,
    };
  }

  # You need at least editbugs to reopen a resolved/verified bug
  if ($bug->status->name eq 'VERIFIED' && !$editbugs) {
    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You require "editbugs" permission to reopen a RESOLVED/VERIFIED bug.',
    };
  }

  # You need at least canconfirm to mark a bug as FIXED
  if ($new_value eq 'FIXED' && !$canconfirm) {
    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You need "canconfirm" permissions to mark a bug as RESOLVED/FIXED.',
    };
  }

  return undef;
}

1;
