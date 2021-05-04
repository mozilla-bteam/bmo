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

sub evaluate_create {
  my ($self, $args) = @_;
  my $bug = $args->{bug};

  # If setting the severity other than default, a comment is required
  if ($bug->bug_severity ne Bugzilla->params->{defaultseverity}
    && (!$bug->comments->[0] || !$bug->comments->[0]->body))
  {
    ThrowUserError('mozchangedield_severity_comment_required', {new => 1});
  }
}

sub evaluate_change {
  my ($self, $args) = @_;
  my $bug     = $args->{bug};
  my $changes = $args->{changes};

  # If changing the severity, a comment is required.
  if (exists $changes->{bug_severity} && !$bug->{added_comments}) {
    ThrowUserError('mozchangedield_severity_comment_required');
  }
}

1;
