# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Marc Schumann <wurblzap@gmail.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Mads Bondo Dydensborg <mbd@dbc.dk>
#                 Noura Elhawary <nelhawar@redhat.com>

package Bugzilla::API::V1::Elastic;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::API::V1::Util qw(validate);
use Bugzilla::Util qw(trim detaint_natural );

sub suggest_users {
  my ($self, $params) = @_;

  Bugzilla->switch_to_shadow_db();

  ThrowCodeError('params_required',
    {function => 'Elastic.suggest_users', params => ['match']})
    unless defined $params->{match};

  ThrowUserError('user_access_by_match_denied') unless Bugzilla->user->id;

  my $results = Bugzilla->elastic->suggest_users($params->{match} . "");
  my @users = map { {
    real_name => $self->type(string => $_->{real_name}),
    name      => $self->type(email  => $_->{name}),
  } } @$results;

  return {users => \@users};
}

1;
