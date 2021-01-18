# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::BugStatus;

use 5.10.1;
use Moo;

use Bugzilla::Constants;
use Bugzilla::Status qw(is_open_state);
use Bugzilla::Util qw(datetime_from);

use DateTime;

sub process_field {
  my ($self, $params) = @_;

  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $editbugs     = $args->{'editbugs'};

  return undef if $field ne 'bug_status';

  # You need at least editbugs to reopen a resolved/verified bug
  if ($old_value eq 'VERIFIED' && !$editbugs) {
    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You require "editbugs" permission to reopen a RESOLVED/VERIFIED bug',
    };
  }

  # Disallow reopening of bugs which have been resolved for > 1 year
  if ( is_open_state($new_value)
    && !is_open_state($old_value)
    && $bug->resolution eq 'FIXED')
  {
    my $days_ago = DateTime->now(time_zone => Bugzilla->local_timezone);
    $days_ago->subtract(days => 365);
    my $last_closed = datetime_from($bug->last_closed_date);
    if ($last_closed lt $days_ago) {
      return {
        result => PRIVILEGES_REQUIRED_EMPOWERED,
        reason => 'Bugs closed as FIXED cannot be reopened after one year',
      };
    }
  }

  return undef;
}
