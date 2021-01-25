# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Teams;
use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Teams qw(team_names get_team_info);

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/config/component_teams/:team')->to('V1::Teams#component_teams', team => '');
}

sub component_teams {
  my ($self) = @_;
  $self->bugzilla->login();
  my $result;
  if (my $team = $self->param('team')) {
    $result = get_team_info($team);
  }
  else {
    $result = team_names();
  }
  return $self->render(json => $result);
}

1;
