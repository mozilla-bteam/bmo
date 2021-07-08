# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::ClearTrackingPriorityS1;

use 5.10.1;
use Moo;

sub evaluate_change {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};
  my $changes   = $args->{changes};

  if ( $changes
    && exists $changes->{bug_severity}
    && $changes->{bug_severity}->[0] eq 'S1')
  {
    # Clear priority
    if ($bug->priority ne '--') {
      $bug->set_priority('--');
      $changes->{priority} = [$bug->priority, '--'];
    }

    # Clear current tracking flags if set to '?', otherwise leave alone
    my $tracking_flags
      = Bugzilla::Extension::TrackingFlags::Flag->match({
      bug_id => $bug->id, is_active => 1,
      });

    foreach my $flag (@{$tracking_flags}) {
      my $flag_name  = $flag->name;
      my $flag_value = $bug->$flag_name;

      # Only interested in tracking flags and flags set to ?
      next if $flag_name !~ /^cf_tracking_/;
      next if $flag_value ne '?';
      next
        if (exists $changes->{$flag_name}
        && $changes->{$flag_name}->[1] !~ /(\?|---)/);

      $flag->bug_flag->remove_from_db();

      $changes->{$flag_name} = [$flag_value, '---'];

      # Update the name/value pair in the bug object
      $bug->{$flag_name} = '---';
    }

    $bug->update($timestamp);
  }
}

1;
