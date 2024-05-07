# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Reminder;

use base qw(Bugzilla::Object);

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Error;

use constant DB_TABLE => 'reminders';

use constant DB_COLUMNS => qw(
  id
  user_id
  bug_id
  note
  remind_when
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => ();

use constant VALIDATORS => {
  user_id     => \&_check_user,
  bug_id      => \&_check_bug_id,
  remind_when => \&_check_when,
};

use constant AUDIT_CREATES => 1;
use constant AUDIT_UPDATES => 1;
use constant AUDIT_REMOVES => 1;
use constant USE_MEMCACHED => 1;

# getters

sub user {
  my ($self) = @_;
  return Bugzilla::User->new({id => $self->{user_id}, cache => 1});
}

sub bug {
  my ($self) = @_;
  return Bugzilla::Bug->new({id => $self->{bug_id}, cache => 1});
}

sub id   { return $_[0]->{id}; }
sub note { return $_[0]->{note}; }
sub when { return $_[0]->{remind_when}; }

# validators

sub _check_user {
  my ($class, $user) = @_;
  $user || ThrowCodeError('param_required', {param => 'user_id'});
}

sub _check_bug_id {
  my ($class, $bug_id) = @_;
  $bug_id || ThrowCodeError('param_required', {param => 'bug_id'});
}

sub _check_when {
  my ($class, $when) = @_;
  $when || ThrowCodeError('param_required', {param => 'remind_when'});
}

1;
