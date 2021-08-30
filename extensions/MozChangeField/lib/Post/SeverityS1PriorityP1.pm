# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::SeverityS1PriorityP1;

use 5.10.1;
use Moo;

use Bugzilla::Field;

use List::MoreUtils qw(any);

sub evaluate_create {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};

  if (
    $bug->bug_severity eq 'S1' && $bug->priority ne 'P1' && any { $_ eq 'P1' }
    @{get_legal_field_values('priority')}
    )
  {
# Should call $bug->update here so set directly
    Bugzilla->dbh->do('UPDATE bugs SET priority = ? WHERE bug_id = ?',
      undef, 'P1', $bug->id);
    $bug->{priority} = 'P1';
  }
}

sub evaluate_change {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};
  my $changes   = $args->{changes};

  if (
    $bug->bug_severity eq 'S1' && $bug->priority ne 'P1' && any { $_ eq 'P1' }
    @{get_legal_field_values('priority')}
    )
  {
    # Cannot call $bug->update here so set directly
    Bugzilla->dbh->do("UPDATE bugs SET priority = 'P1' WHERE bug_id = ?",
      undef, $bug->id);
    $changes->{priority} = [$bug->priority, 'P1'];
    $bug->{priority}     = 'P1';
  }
}

1;
