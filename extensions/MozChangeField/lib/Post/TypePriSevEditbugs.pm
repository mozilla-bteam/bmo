# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::TypePriSevEditbugs;

use 5.10.1;
use Moo;

use Bugzilla::Constants;

sub evaluate_change {
  my ($self, $args) = @_;
  my $changes  = $args->{changes};
  my $editbugs = $args->{editbugs};

  # If changing the bug_type, severity, or priority, editbugs is required.
  foreach my $field (qw(bug_type bug_severity priority)) {
    if (exists $changes->{$field} && !$editbugs) {
      ThrowUserError('mozchangefield_field_needs_editbugs', {field => $field});
    }
  }
}

1;
