# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::CommentOnSeverity;

use 5.10.1;
use Moo;

use Bugzilla::Error;
use Bugzilla::Util qw(trim);

use constant DEFAULT_COMMENT =>
  'Changing severity to S? because of <rationale>.';

sub evaluate_change {
  my ($self, $args) = @_;
  my $bug     = $args->{bug};
  my $changes = $args->{changes};

  # If changing the severity, a comment is required.
  if (
    exists $changes->{bug_severity}
    && (!$bug->{added_comments}
      || trim($bug->{added_comments}->[0]->body) eq DEFAULT_COMMENT)
    )
  {
    ThrowUserError('mozchangefield_severity_comment_required');
  }
}

1;
