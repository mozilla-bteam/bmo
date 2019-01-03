# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::OAuth2;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin::OAuth2::Server';

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util;
use Bugzilla::Token;
use DateTime;
use List::MoreUtils qw(any);
use Mojo::Util qw(secure_compare);
use Try::Tiny;

sub register {
  my ($self, $app, $conf) = @_;

  $conf->{login_resource_owner}      = \&_resource_owner_logged_in;
  $conf->{confirm_by_resource_owner} = \&_resource_owner_confirm_scopes;
  $conf->{verify_client}             = \&_verify_client;
  $conf->{store_auth_code}           = \&_store_auth_code;
  $conf->{verify_auth_code}          = \&_verify_auth_code;
  $conf->{store_access_token}        = \&_store_access_token;
  $conf->{verify_access_token}       = \&_verify_access_token;
  $conf->{jwt_secret}                = Bugzilla->localconfig->{jwt_secret};
  $conf->{jwt_claims}                = sub {
    my $args = shift;
    if (!$args->{user_id}) {
      return (user_id => Bugzilla->user->id);
    }
  };

  $app->helper(
    'bugzilla.oauth' => sub {
      my ($c, @scopes) = @_;

      my $oauth = $c->oauth(@scopes);

      if ($oauth && $oauth->{user_id}) {
        my $user = Bugzilla::User->check({id => $oauth->{user_id}, cache => 1});
        return undef if !$user->is_enabled;
        Bugzilla->set_user($user);
        return $user;
      }

      return undef;
    }
  );

  return $self->SUPER::register($app, $conf);
}

sub _resource_owner_logged_in {
  my (%args) = @_;
  my $c = $args{mojo_controller};

  $c->session->{override_login_target} = $c->url_for('current');
  $c->session->{cgi_params}            = $c->req->params->to_hash;

  $c->bugzilla->login(LOGIN_REQUIRED) || return undef;

  delete $c->session->{override_login_target};
  delete $c->session->{cgi_params};

  return 1;
}

sub _resource_owner_confirm_scopes {
  my (%args) = @_;
  my ($c, $client_id, $scopes_ref)
    = @args{qw/ mojo_controller client_id scopes /};

  my $is_allowed = $c->param("oauth_confirm_${client_id}");

  # if user hasn't yet allowed the client access, or if they denied
  # access last time, we check [again] with the user for access
  if (!defined $is_allowed) {
    my $client
      = Bugzilla->dbh->selectrow_hashref(
      'SELECT * FROM oauth2_client WHERE client_id = ?',
      undef, $client_id);
    my $vars = {
      client => $client,
      scopes => $scopes_ref,
      token  => scalar issue_session_token('oauth_confirm_scopes')
    };
    $c->stash(%{$vars});
    $c->render(template => 'account/auth/confirm_scopes', handler => 'bugzilla');
    return undef;
  }

  my $token = $c->param('token');
  check_token_data($token, 'oauth_confirm_scopes');
  delete_token($token);

  return $is_allowed;
}

sub _verify_client {
  my (%args) = @_;
  my ($c, $client_id, $scopes_ref)
    = @args{qw/ mojo_controller client_id scopes /};
  my $dbh = Bugzilla->dbh;

  if (!@{$scopes_ref}) {
    INFO('Client did not provide scopes');
    return (0, 'invalid_scope');
  }

  if (
    my $client_data = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_client WHERE client_id = ?',
      undef, $client_id
    )
    )
  {
    if (!$client_data->{active}) {
      INFO("Client ($client_id) is not active");
      return (0, 'unauthorized_client');
    }

    if ($scopes_ref) {
      my $client_scopes = $dbh->selectcol_arrayref(
        'SELECT oauth2_scope.description FROM oauth2_scope
                JOIN oauth2_client_scope ON oauth2_scope.id = oauth2_client_scope.scope_id
          WHERE oauth2_client_scope.client_id = ?', undef, $client_data->{id}
      );

      foreach my $scope (@{$scopes_ref // []}) {
        return (0, 'invalid_grant') if !_has_scope($scope, $client_scopes);
      }
    }

    return (1);
  }

  INFO("Client ($client_id) does not exist");
  return (0, 'unauthorized_client');
}

sub _verify_auth_code {
  my (%args) = @_;
  my ($c, $client_id, $client_secret, $auth_code, $uri)
    = @args{qw/ mojo_controller client_id client_secret auth_code redirect_uri /};
  my $dbh = Bugzilla->dbh;

  my ($res, $jwt_claims) = _get_jwt_claims($auth_code);
  return (0, 'invalid_jwt') unless $res;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $jwt_claims->{client});
  $client_data || return (0, 'unauthorized_client');

  my $auth_code_data
    = $dbh->selectrow_hashref(
    'SELECT * FROM oauth2_auth_code WHERE client_id = ? AND auth_code = ?',
    undef, $client_data->{id}, $auth_code);

  return (0, 'invalid_jwt') unless $jwt_claims->{jti} eq $auth_code_data->{jti};

  if (!$auth_code_data
    or $auth_code_data->{verified}
    or ($uri ne $auth_code_data->{redirect_uri})
    or (datetime_from($auth_code_data->{expires})->epoch <= time)
    or !secure_compare($client_secret, $client_data->{secret}))
  {
    INFO('Auth code does not exist') if !$auth_code;
    INFO('Client secret does not match')
      if !secure_compare($client_secret, $client_data->{secret});

    if ($auth_code) {
      INFO('Client secret does not match')
        if ($uri && $auth_code_data->{redirect_uri} ne $uri);
      INFO('Auth code expired') if ($auth_code_data->{expires} <= time);

      if ($auth_code_data->{verified}) {

        # the auth code has been used before - we must revoke the auth code
        # and any associated access tokens (same client_id and user_id)
        INFO( 'Auth code already used to get access token, '
            . 'revoking all associated access tokens');
        $dbh->do('DELETE FROM oauth2_auth_code WHERE auth_code = ?', undef, $auth_code);
        $dbh->do('DELETE FROM oauth2_access_token WHERE client_id = ? AND user_id = ?',
          undef, $client_data->{id}, $jwt_claims->{user_id});
      }
    }

    return (0, 'invalid_grant');
  }

  $dbh->do('UPDATE oauth2_auth_code SET verified = 1 WHERE auth_code = ?',
    undef, $auth_code);

  return ($client_id, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
}

sub _store_auth_code {
  my (%args) = @_;
  my ($c, $auth_code, $client_id, $expires_in, $uri, $scopes_ref)
    = @args{
    qw/ mojo_controller auth_code client_id expires_in redirect_uri scopes /};
  my $dbh = Bugzilla->dbh;

  my ($res, $jwt_claims) = _get_jwt_claims($auth_code);
  return (0, 'invalid_jwt') unless $res;

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $jwt_claims->{client});

  $dbh->do(
    'INSERT INTO oauth2_auth_code (auth_code, client_id, user_id, jti, expires, redirect_uri) VALUES (?, ?, ?, ?, ?, ?)',
    undef,
    $auth_code,
    $client_data->{id},
    $jwt_claims->{user_id},
    $jwt_claims->{jti},
    DateTime->from_epoch(epoch => time + $expires_in),
    $uri
  );

  return undef;
}

sub _store_access_token {
  my (%args) = @_;
  my ($c, $client_id, $auth_code, $access_token, $refresh_token, $expires_in,
    $scopes, $old_refresh_token)
    = @args{
    qw/ mojo_controller client_id auth_code access_token refresh_token expires_in scopes old_refresh_token /
    };
  my $dbh = Bugzilla->dbh;
  my ($res, $access_jwt_claims, $refresh_jwt_claims, $old_refresh_jwt_claims,
    $auth_jwt_claims);

  ($res, $access_jwt_claims) = _get_jwt_claims($access_token);
  return (0, 'invalid_jwt') unless $res;

  ($res, $refresh_jwt_claims) = _get_jwt_claims($refresh_token);
  return (0, 'invalid_jwt') unless $res;

  my $user_id;
  if (!defined $auth_code && $old_refresh_token) {

    # must have generated an access token via a refresh token so revoke the
    # old access token and refresh token (also copy required data if missing)
    ($res, $old_refresh_jwt_claims) = _get_jwt_claims($old_refresh_token);
    return (0, 'invalid_jwt') unless $res;

    my $prev_refresh_token
      = $dbh->selectrow_hashref(
      'SELECT * FROM oauth2_refresh_token WHERE refresh_token = ?',
      undef, $old_refresh_token);

    $scopes //= $old_refresh_jwt_claims->{scope};
    $user_id = $old_refresh_jwt_claims->{user_id};

    INFO('Revoking old access tokens (refresh)');
    $dbh->do('DELETE FROM oauth2_access_token WHERE id = ?',
      undef, $prev_refresh_token->{access_token_id});
  }
  else {
    ($res, $auth_jwt_claims) = _get_jwt_claims($auth_code);
    return (0, 'invalid_jwt') unless $res;
    $user_id = $auth_jwt_claims->{user_id};
  }

  if (ref($client_id)) {
    $scopes    = $client_id->{scope};
    $client_id = $client_id->{client_id};
  }

  my $client_data
    = $dbh->selectrow_hashref('SELECT * FROM oauth2_client WHERE client_id = ?',
    undef, $client_id);

  # If the client has en existing access/refesh tokens, we need to revoke them
  $dbh->do('DELETE FROM oauth2_access_token WHERE client_id = ? AND user_id = ?',
    undef, $client_data->{id}, $access_jwt_claims->{user_id});
  $dbh->do('DELETE FROM oauth2_refresh_token WHERE client_id = ? AND user_id = ?',
    undef, $client_data->{id}, $refresh_jwt_claims->{user_id});

  $dbh->do(
    'INSERT INTO oauth2_access_token (access_token, client_id, jti, user_id, expires) VALUES (?, ?, ?, ?, ?)',
    undef,
    $access_token,
    $client_data->{id},
    $access_jwt_claims->{jti},
    $access_jwt_claims->{user_id},
    DateTime->from_epoch(epoch => time + $expires_in)
  );

  my $access_token_data
    = $dbh->selectrow_hashref(
    'SELECT * FROM oauth2_access_token WHERE access_token = ?',
    undef, $access_token);

  $dbh->do(
    'INSERT INTO oauth2_refresh_token (refresh_token, access_token_id, client_id, jti, user_id) VALUES (?, ?, ?, ?, ?)',
    undef,
    $refresh_token,
    $access_token_data->{id},
    $client_data->{id},
    $refresh_jwt_claims->{jti},
    $refresh_jwt_claims->{user_id}
  );

  return undef;
}

sub _verify_access_token {
  my (%args) = @_;
  my ($c, $access_token, $scopes_ref, $is_refresh_token)
    = @args{qw/ mojo_controller access_token scopes is_refresh_token /};
  my $dbh = Bugzilla->dbh;

  my ($res, $jwt_claims) = _get_jwt_claims($access_token);
  return (0, 'invalid_jwt') unless $res;

  my $refresh_token_data
    = $dbh->selectrow_hashref(
    'SELECT * FROM oauth2_refresh_token WHERE refresh_token = ?',
    undef, $access_token);

  if ($is_refresh_token && $refresh_token_data) {
    return (0, 'invalid_jwt')
      unless $jwt_claims->{jti} eq $refresh_token_data->{jti};

    if ($scopes_ref) {
      foreach my $scope (@{$scopes_ref // []}) {
        return (0, 'invalid_grant') if !_has_scope($scope, $jwt_claims->{scopes});
      }
    }

    return ($jwt_claims, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
  }

  my $access_token_data
    = $dbh->selectrow_hashref(
    'SELECT * FROM oauth2_access_token WHERE access_token = ?',
    undef, $access_token);

  if ($access_token_data) {
    return (0, 'invalid_jwt')
      unless $jwt_claims->{jti} eq $access_token_data->{jti};

    if (datetime_from($access_token_data->{expires})->epoch <= time) {
      INFO('Access token has expired');
      $dbh->do('DELETE FROM oauth2_access_token WHERE access_token = ?',
        undef, $access_token);
      return (0, 'invalid_grant');
    }
    elsif ($scopes_ref) {
      foreach my $scope (@{$scopes_ref // []}) {
        return (0, 'invalid_grant') if !_has_scope($scope, $jwt_claims->{scopes});
      }
    }

    return ($jwt_claims, undef, $jwt_claims->{scopes}, $jwt_claims->{user_id});
  }
  else {
    INFO('Access token does not exist');
    return (0, 'invalid_grant');
  }
}

sub _get_jwt_claims {
  my ($jwt) = @_;
  my ($claims, $jwt_error);

  try {
    $claims = Bugzilla->jwt->decode($jwt);
  }
  catch {
    INFO("Error decoding JWT: $_");
    $jwt_error = 1;
  };

  return (0) if $jwt_error;
  return (1, $claims);
}

sub _has_scope {
  my ($scope, $available_scopes) = @_;
  return any {$scope} @{$available_scopes // []};
}

1;
