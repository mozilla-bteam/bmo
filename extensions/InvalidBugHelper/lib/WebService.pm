# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::InvalidBugHelper::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Comment;
use Bugzilla::Constants;
use Bugzilla::Error;
use constant PUBLIC_METHODS => qw(close_as_invalid);

sub close_as_invalid {
  my ($self, $params) = @_;
  my $user = Bugzilla->login(LOGIN_REQUIRED);
  my $dbh  = Bugzilla->dbh;

  $user->in_group('editbugs')
    || ThrowUserError('auth_failure',
    {group => 'editbugs', action => 'update', object => 'bug'});

  my $bug_id = $params->{bug_id}
    || ThrowCodeError('param_required',
    {function => 'InvalidBugHelper.close_as_invalid', param => 'bug_id'});

  my $bug = Bugzilla::Bug->check({id => $bug_id});

  # Snapshot reporter comments and flags before any mutations.
  my @reporter_comments
    = grep { $_->author->id == $bug->reporter->id } @{$bug->comments};
  my @clear_flags = map { {id => $_->id, status => 'X'} }
    grep { $_->type->name eq 'needinfo' } @{$bug->flags};

  my $warning_text = Bugzilla->params->{invalidbughelper_warning_text}
    || 'This bug has been marked as invalid.';

  $dbh->bz_start_transaction();

  # Clear all needinfo flags.
  $bug->set_flags(\@clear_flags, []) if @clear_flags;

  # Relocate the bug, resolve it, reset ownership, and post the warning comment.
  $bug->set_all({
    product           => 'Invalid Bugs',
    component         => 'General',
    bug_status        => 'RESOLVED',
    resolution        => 'INVALID',
    reset_assigned_to => 1,
    reset_qa_contact  => 1,
    comment           => {body => $warning_text},
  });

  $bug->update();

  # Tag every reporter comment as spam (triggers AntiSpam user-disable logic).
  if (Bugzilla->params->{comment_taggers_group} && $user->can_tag_comments()) {
    foreach my $comment (@reporter_comments) {
      $comment->add_tag('spam');
      $comment->update();
    }
  }

  $dbh->bz_commit_transaction();

  return {
    id      => $self->type('int',    $bug->id),
    product => $self->type('string', $bug->product),
    status  => $self->type('string', $bug->bug_status),
  };
}

sub rest_resources {
  return [
    qr{^/invalid_bug_helper/close/(\d+)$},
    {
      POST => {
        method => 'close_as_invalid',
        params => sub { {bug_id => $_[0]} },
      },
    },
  ];
}

1;
