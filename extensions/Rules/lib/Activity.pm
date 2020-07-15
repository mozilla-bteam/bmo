# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Activity;

use 5.10.1;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Config qw(:admin);
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;

sub setup_routes {
  my ($class, $routes) = @_;

  # View and rollback rules activity
  my $rules_route = $routes->under(
    '/admin/rules' => sub {
      my ($c) = @_;
      my $user = $c->bugzilla->login(LOGIN_REQUIRED) || return undef;
      $user->in_group('admin')
        || ThrowUserError('auth_failure',
        {group => 'admin', action => 'edit', object => 'rules_activity'});
      return 1;
    }
  );

  $rules_route->any('/activity')->to('Rules::Activity#activity')
    ->name('show_activity');
  $rules_route->any('/rollback/:id')->to('Rules::Activity#rollback')
    ->name('rollback_rules');
}

# Show Rules activity
sub activity {
  my ($self) = @_;
  $self->stash(activity => get_activity());
  return $self->render(template => 'admin/rules/activity', handler => 'bugzilla');
}

# Rollback a previous version of the Rules
sub rollback {
  my ($self) = @_;
  my $dbh    = Bugzilla->dbh;
  my $id     = $self->param('id');
  my $activity = get_activity($id);

  # Display confirmation screen
  if (!$self->param('submit')) {
    my $token = issue_session_token('rules_rollback');
    $self->stash({activity => $activity->[0], token => $token});
    return $self->render(
      template => 'admin/rules/rollback_confirm',
      handler  => 'bugzilla',
    );
  }

  my $token = $self->param('token');
  check_token_data($token, 'rules_rollback');

  # Record new Rules configuration
  SetParam('change_field_rules', $activity->[0]->{rules});
  write_params();

  delete_token($token);

  # Return to Rules config panel
  my $url = $self->url_for('editparamscgi')->query(section => 'rules');
  $self->redirect_to($url);
}

# Record the new rules in the activity table
sub log_activity {
  my ($class, $toml) = @_;
  Bugzilla->dbh->do(
    'INSERT INTO rules_activity (who, change_when, rules) VALUES (?, now(), ?)',
    undef, Bugzilla->user->id, $toml);
}

sub get_activity {
  my ($id) = @_;
  my $dbh = Bugzilla->dbh;

  my $where = '1=1';
  if ($id && $id =~ /^\d+$/sxm) {
    $where = "rules_activity.id = $id";
  }

  my $query
    = 'SELECT rules_activity.id, rules_activity.who, '
    . $dbh->sql_date_format('rules_activity.change_when', '%Y-%m-%d %H:%i:%s')
    . " AS change_when, rules_activity.rules
         FROM rules_activity WHERE $where
     ORDER BY rules_activity.change_when DESC";
  my $sth = $dbh->prepare($query);
  $sth->execute();

  my @activity;
  while (my $change = $sth->fetchrow_hashref()) {
    push(
      @activity,
      {
        id    => $change->{id},
        who   => Bugzilla::User->new({id => $change->{who}, cache => 1}),
        when  => $change->{change_when},
        rules => $change->{rules},
      }
    );
  }

  return \@activity;
}

1;
