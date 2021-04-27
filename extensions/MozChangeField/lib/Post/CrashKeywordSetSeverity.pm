# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::CrashKeywordSetSeverity;

use 5.10.1;
use Moo;

use Bugzilla::Field;

use List::MoreUtils qw(any);

sub evaluate_create {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};

  if ( $bug->has_keyword('crash')
    && $bug->bug_severity eq Bugzilla->params->{defaultseverity}
    && grep { $_ eq 'S2' } @{get_legal_field_values('bug_severity')})
  {
    $bug->set_severity('S2');
    $bug->update($timestamp);
  }
}

1;
