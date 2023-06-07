# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::SearchAPI::API::V1::LastSeen;

use Mojo::Base qw(Mojolicious::Controller);

use Bugzilla::Extension::SearchAPI::Util qw(bug_to_hash named_params);

use Bugzilla::Bug;
use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('search/needinfo_last_seen')
    ->to('SearchAPI::API::V1::LastSeen#needinfo_last_seen');
  $r->get('search/assignee_last_seen')
    ->to('SearchAPI::API::V1::LastSeen#assignee_last_seen');
}

sub needinfo_last_seen {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $dbh = Bugzilla->dbh;

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  my $days = $self->param('days');

  my $query = "SELECT bugs.bug_id
         FROM bugs JOIN flags ON bugs.bug_id = flags.bug_id
              JOIN profiles ON flags.requestee_id = profiles.userid
        WHERE flags.type_id = (SELECT id FROM flagtypes WHERE name = 'needinfo')
              AND bugs.resolution = ''
              AND profiles.last_seen_date < "
    . $dbh->sql_date_math('NOW()', '-', ':days', 'DAY')
    . ' LIMIT 1000';

  my ($updated_query, $values) = named_params($query, {days => $days});

  my $ids = $dbh->selectcol_arrayref($updated_query, undef, @{$values});

  my $bugs = Bugzilla::Bug->new_from_list($ids);
  $bugs = $user->visible_bugs($bugs);

  my $result = [];
  foreach my $bug (@{$bugs}) {
    push @{$result}, bug_to_hash($bug, {flags => 1});
  }

  return $self->render(json => {result => $result});
}

sub assignee_last_seen {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $dbh = Bugzilla->dbh;

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  my $days = $self->param('days');

  my $query = "SELECT bugs.bug_id
         FROM bugs JOIN profiles ON bugs.assigned_to = profiles.userid
        WHERE bugs.resolution = ''
              AND profiles.last_seen_date < "
    . $dbh->sql_date_math('NOW()', '-', ':days', 'DAY')
    . ' LIMIT 1000';

  my ($updated_query, $values) = named_params($query, {days => $days});

  my $ids = $dbh->selectcol_arrayref($updated_query, undef, @{$values});

  my $bugs = Bugzilla::Bug->new_from_list($ids);
  $bugs = $user->visible_bugs($bugs);

  my $result = [];
  foreach my $bug (@{$bugs}) {
    push @{$result}, bug_to_hash($bug, {assignee => 1});
  }

  return $self->render(json => {result => $result});
}

1;
