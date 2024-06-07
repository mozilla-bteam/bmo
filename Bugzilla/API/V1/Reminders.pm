# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Reminders;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );
use Mojo::JSON qw( decode_json false true);

use Bugzilla::Constants;
use Bugzilla::Reminder;

use Try::Tiny;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/reminder')->to('V1::Reminders#list');
  $r->get('/reminder/:id')->to('V1::Reminders#list');
  $r->post('/reminder')->to('V1::Reminders#add');
  $r->delete('/reminder/:id')->to('V1::Reminders#remove');
}

sub list {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);
  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  my $params = {user_id => $user->id};
  $params->{id}   = $self->param('id') if $self->param('id');
  $params->{sent} = 0                  if !$self->param('all');

  my $reminders = Bugzilla::Reminder->match($params);

  # Requested single reminder
  if ($self->param('id')) {
    return $self->render(json => $self->_reminder_to_hash($reminders->[0]));
  }

  my $results = [];
  foreach my $reminder (@{$reminders}) {
    push @{$results}, $self->_reminder_to_hash($reminder);
  }

  return $self->render(json => {reminders => $results});
}

sub add {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);
  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  # Do not allow adding of reminders if feature is not enabled
  # or user does not have permission to do so
  return $self->render(json => {})
    unless Bugzilla->params->{reminders_enabled}
    && $user->in_group(Bugzilla->params->{reminders_group});

  my $params = {};
  try {
    $params = decode_json($self->req->body);
  }
  catch {
    return $self->user_error('rest_malformed_json');
  };

  my $bug_id      = $params->{bug_id};
  my $note        = $params->{note};
  my $reminder_ts = $params->{reminder_ts};

  my $reminder = Bugzilla::Reminder->create({
    user_id     => $user->id,
    bug_id      => $bug_id,
    reminder_ts => $reminder_ts,
    note        => $note,
  });

  return $self->render(json => $self->_reminder_to_hash($reminder));
}

sub remove {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);
  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  # You can only delete your own so pass in user_id as well
  my $reminder
    = Bugzilla::Reminder->new({user_id => $user->id, id => $self->param('id')});

  my $success = 0;
  if ($reminder) {
    $reminder->remove_from_db();
    $success = 1;
  }

  return $self->render(json => {success => $success});
}

sub _reminder_to_hash {
  my ($self, $reminder) = @_;
  return {
    id          => $reminder->id,
    bug_id      => $reminder->bug_id,
    note        => $reminder->note,
    reminder_ts => $reminder->reminder_ts,
    creation_ts => $reminder->creation_ts,
    sent        => ($reminder->sent ? true : false),
  };
}

1;
