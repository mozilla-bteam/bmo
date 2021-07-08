# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM::API::V1::User;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Extension::MozillaIAM::Util qw(verify_token);
use Bugzilla::Logging;

use Date::Format;
use JSON::Validator::Joi qw(joi);

sub setup_routes {
  my ($class, $r) = @_;
  $r->post('/mozillaiam/user/update')->to('MozillaIAM::API::V1::User#update');
  $r->post('/mozillaiam/v1/user/update')->to('MozillaIAM::API::V1::User#update');
}

#  {
#    "operation": update,
#    "id": ad|Mozilla-LDAP|dinomcvouch,
#    "time": {epoch timestamp},
#  }

sub update {
  my ($self) = @_;

  return $self->render(status => 200, text => 'OK!')
    if !Bugzilla->params->{mozilla_iam_enabled};

  # Verify JWT token
  unless ($ENV{CI} || $ENV{NO_VERIFY_TOKEN}) {
    my $authorization_header = $self->tx->req->headers->header('Authorization');
    verify_token($authorization_header)
      || return $self->user_error('mozilla_iam_token_error');
  }

  # Validate JSON input
  my $params = $self->req->json;
  my @errors = joi->object->props(
    operation => joi->string->enum(['create', 'update', 'delete'])->required,
    id        => joi->string->required,
    time      => joi->integer->required,
  )->validate($params);
  return $self->user_error('api_input_schema_error', {errors => \@errors})
    if @errors;

  my $operation = $params->{operation};
  my $user_id   = $params->{id};
  my $mod_time  = $params->{time};

  DEBUG("operation: $operation user_id: $user_id, mod_time: $mod_time");

  # Queue up the id to be processed by the person server
  $mod_time = time2str('%Y-%m-%d %k-%M-S', $mod_time);
  Bugzilla->dbh->do(
    'INSERT INTO mozilla_iam_updates (type, value, mod_time) VALUES (?, ?, ?)',
    undef, $operation, $user_id, $mod_time);

  return $self->render(status => 200, text => 'OK!');
}

1;
