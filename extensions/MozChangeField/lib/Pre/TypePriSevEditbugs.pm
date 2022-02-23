# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Pre::TypePriSevEditbugs;

use 5.10.1;
use Moo;

use Bugzilla::Constants;
use Bugzilla::Logging;

sub evaluate_change {
  my ($self, $args) = @_;

  my $field    = $args->{'field'};
  my $editbugs = $args->{'editbugs'};

  # The user needs to have 'editbugs' permission to change the type, severity
  # and priority fields.
  if (($field eq 'bug_type' || $field eq 'bug_severity' || $field eq 'priority')
    && !$editbugs)
  {
    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You need "editbugs" permissions to change this field.',
    };
  }

  return undef;
}

1;
