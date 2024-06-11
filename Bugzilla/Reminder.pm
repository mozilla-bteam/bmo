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
  creation_ts
  reminder_ts
  sent
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => qw(
  sent
);

use constant VALIDATORS => {
  user_id     => \&_check_user_id,
  bug_id      => \&_check_bug_id,
  creation_ts => \&_check_creation_ts,
  reminder_ts => \&_check_reminder_ts,
};

use constant AUDIT_CREATES => 1;
use constant AUDIT_UPDATES => 1;
use constant AUDIT_REMOVES => 1;
use constant USE_MEMCACHED => 0;

# getters

sub user {
  my ($self) = @_;
  return Bugzilla::User->new({id => $self->{user_id}, cache => 1});
}

sub bug {
  my ($self) = @_;
  return Bugzilla::Bug->new({id => $self->{bug_id}, cache => 1});
}

sub reminder_ts {
  my ($self) = @_;
  return $self->{reminder_ts} ? datetime_from($self->{reminder_ts}) : undef;
}

sub creation_ts {
  my ($self) = @_;
  return $self->{creation_ts} ? datetime_from($self->{creation_ts}) : undef;
}

sub id   { return $_[0]->{id}; }
sub note { return $_[0]->{note}; }
sub sent { return $_[0]->{sent}; }

# setters

sub set_sent { $_[0]->set('sent', $_[1]); }

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

sub _check_reminder_ts {
  my ($class, $reminder_ts) = @_;
  $reminder_ts = trim($reminder_ts);

# check that the date is valid and the correct format
  validate_date($reminder_ts)
    || ThrowUserError('illegal_date',
    {date => $reminder_ts, format => 'YYYY-MM-DD'});
  return $reminder_ts;
}

sub _check_creation_ts {
  return Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
}

1;
