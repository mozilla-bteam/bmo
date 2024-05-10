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
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util qw(datetime_from trim validate_date);

use DateTime;

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
  user_id     => \&_check_user_id,
  bug_id      => \&_check_bug_id,
  remind_when => \&_check_remind_when,
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

sub expired {
  my ($self) = @_;
  return $self->remind_when < DateTime->now;
}

sub remind_when {
  my ($self) = @_;
  return $self->{remind_when}
    ? datetime_from($self->{remind_when})
    : undef;
}

sub id   { return $_[0]->{id}; }
sub note { return $_[0]->{note}; }

# validators

sub _check_user_id {
  my ($class, $user_id) = @_;

  # check that the user id is a valid user
  return Bugzilla::User->check({id => $user_id, cache => 1})->id;
}

sub _check_bug_id {
  my ($class, $bug_id) = @_;

  # check that the value is a valid, visible bug id
  return Bugzilla::Bug->check({id => $bug_id, cache => 1})->id;
}

sub _check_remind_when {
  my ($class, $when) = @_;
  $when = trim($when);
  return undef if !$when;

# check that the date is valid and the correct format
  validate_date($when)
    || ThrowUserError('illegal_date', {date => $when, format => 'YYYY-MM-DD'});
  return $when;
}

1;
