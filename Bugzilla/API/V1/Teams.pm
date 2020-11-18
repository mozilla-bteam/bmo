# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Teams;
use 5.10.1;
use Bugzilla::Constants;
use Mojo::Base qw( Mojolicious::Controller );
use JSON::MaybeXS qw(decode_json);

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/config/component_teams')->to('V1::Teams#component_teams');
  $r->get('/config/component_security_teams')->to('V1::Teams#component_security_teams');
}

sub component_teams {
  my ($self) = @_;
  $self->bugzilla->login(LOGIN_REQUIRED)
    || return $self->render(status => 401, text => 'Unauthorized');
  $self->render(
    json => decode_json(Bugzilla->params->{report_component_teams})
  );
}

sub component_security_teams {
  my ($self) = @_;
  $self->bugzilla->login(LOGIN_REQUIRED)
    || return $self->render(status => 401, text => 'Unauthorized');
  $self->render(
    json => decode_json(Bugzilla->params->{report_secbugs_teams})
  );
}

1;
