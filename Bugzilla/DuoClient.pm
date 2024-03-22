# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Adapted from https://github.com/duosecurity/duo_universal_python/blob/main/duo_universal/client.py

package Bugzilla::DuoClient;

use 5.10.1;
use Moo;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util qw(generate_random_password mojo_user_agent);

use Mojo::JWT;
use Mojo::URL;
use Mojo::Util qw(dumper);
use Try::Tiny;
use Types::Standard -types;

use constant JTI_LENGTH                     => 36;
use constant MINIMUM_STATE_LENGTH           => 22;
use constant MAXIMUM_STATE_LENGTH           => 1024;
use constant JWT_DEFAULT_EXPIRATION_SECONDS => 300;

use constant ERR_USERNAME     => 'The Duo username was invalid.';
use constant ERR_CODE         => 'The Duo authorization code was missing.';
use constant ERR_HEALTH_CHECK => 'The Duo service health check failed.';
use constant ERR_TOKEN_ERROR =>
  'The Duo service had an error obtaining authorization token.';
use constant ERR_STATE_LEN => 'The Duo state must be at least '
  . MINIMUM_STATE_LENGTH
  . ' characters long and no longer than '
  . MAXIMUM_STATE_LENGTH
  . ' characters.';

use constant OAUTH_V1_HEALTH_CHECK_ENDPOINT => '/oauth/v1/health_check';
use constant OAUTH_V1_AUTHORIZE_ENDPOINT    => '/oauth/v1/authorize';
use constant OAUTH_V1_TOKEN_ENDPOINT        => '/oauth/v1/token';
use constant CLIENT_ASSERT_TYPE =>
  'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';

#########################
#    Initialization     #
#########################

has uri           => (is => 'ro', required => 1, isa => Str);
has client_id     => (is => 'ro', required => 1, isa => Str);
has client_secret => (is => 'ro', required => 1, isa => Str);
has redirect_uri => (
  is      => 'ro',
  default => Bugzilla->localconfig->urlbase . 'mfa/duo/callback'
);

#########################
#    Private Methods    #
#########################

sub _create_jwt_args {
  my ($self, $endpoint) = @_;

  my $jwt_args = {
    'iss' => $self->client_id,
    'sub' => $self->client_id,
    'aud' => $endpoint,
    'exp' => time() + JWT_DEFAULT_EXPIRATION_SECONDS,
    'jti' => generate_random_password(JTI_LENGTH)
  };

  return $jwt_args;
}

#########################
#    Public Methods     #
#########################

# Checks whether Duo is available.
#
# Returns:
# {'response': {'timestamp': <int:unix timestamp>}, 'stat': 'OK'}
#
# Raises:
# Exception on error for invalid credentials or problem connecting to Duo
sub health_check {
  my ($self) = @_;

  my $health_check_uri
    = Mojo::URL->new($self->uri)->path(OAUTH_V1_HEALTH_CHECK_ENDPOINT);
  my $jwt_args = $self->_create_jwt_args($health_check_uri->to_string);

  # If we are running in a local environment, the backend 
  # host needs to be different than the redirect host
  if ($ENV{BZ_DUO_BACKEND_HOST}) {
    $health_check_uri->host($ENV{BZ_DUO_BACKEND_HOST});
  }

  my $client_assertion = Mojo::JWT->new(
    claims    => $jwt_args,
    secret    => $self->client_secret,
    algorithm => 'HS512'
  )->encode;

  my $all_args
    = {'client_assertion' => $client_assertion, 'client_id' => $self->client_id};

  DEBUG(dumper $all_args);

  try {
    my $result
      = mojo_user_agent()->post($health_check_uri, form => $all_args)->result;
    die $result->message if !$result->is_success;

    my $data = $result->json;

    DEBUG(dumper $data);

    if ($data->{stat} ne 'OK') {
      die $data->{stat};
    }

    return $data;
  }
  catch {
    WARN($_);
    ThrowCodeError('duo_client_error', {reason => ERR_HEALTH_CHECK});
  };
}

# Generate uri to Duo's prompt
#
# Arguments:
#
# username -- username trying to authenticate with Duo
# state    -- Randomly generated character string of at least 22
#             chars returned to the integration by Duo after 2FA
#
# Returns:
#
# Authorization uri to redirect to for the Duo prompt
sub create_auth_url {
  my ($self, $username, $state) = @_;

  if ( !$state
    || length $state > MAXIMUM_STATE_LENGTH
    || length $state < MINIMUM_STATE_LENGTH)
  {
    ThrowCodeError('duo_client_error', {reason => ERR_STATE_LEN});
  }
  if (!$username) {
    ThrowCodeError('duo_client_error', {reason => ERR_USERNAME});
  }

  my $authorization_uri = Mojo::URL->new($self->uri)->path(OAUTH_V1_AUTHORIZE_ENDPOINT);
  my $jwt_args = $self->_create_jwt_args($authorization_uri->to_string);

  # Add additional key/value pairs to the standard token needed for authorization
  $jwt_args->{scope}                  = 'openid';
  $jwt_args->{redirect_uri}           = $self->redirect_uri;
  $jwt_args->{client_id}              = $self->client_id;
  $jwt_args->{state}                  = $state;
  $jwt_args->{response_type}          = 'code';
  $jwt_args->{duo_uname}              = $username;
  $jwt_args->{use_duo_code_attribute} = 1;

  my $request_jwt = Mojo::JWT->new(
    claims    => $jwt_args,
    secret    => $self->client_secret,
    algorithm => 'HS512'
  )->encode;

  my $all_args = {
    'response_type' => 'code',
    'client_id'     => $self->client_id,
    'request'       => $request_jwt,
  };

  $authorization_uri->query($all_args);

  return $authorization_uri->to_string;
}

# Exchange the duo_code for a token with Duo to determine
# if the auth was successful.
#
# Argument:
#
# duoCode  -- Authentication session transaction id
#             returned by Duo
# username -- Name of the user authenticating with Duo
#
# Return:
#
# A token with meta-data about the auth
#
# Raises:
#
# DuoException on error for invalid duo_codes, invalid credentials,
# or problems connecting to Duo
sub exchange_authorization_code_for_2fa_result {
  my ($self, $duo_code, $username) = @_;

  if (!$duo_code) {
    ThrowCodeError('duo_client_error', {reason => ERR_CODE});
  }

  my $token_uri = Mojo::URL->new($self->uri)->path(OAUTH_V1_TOKEN_ENDPOINT);
  my $jwt_args  = $self->_create_jwt_args($token_uri->to_string);

  # If we are running in a local environment, the backend
  # host needs to be different than the redirect host
  if ($ENV{BZ_DUO_BACKEND_HOST}) {
    $token_uri->host($ENV{BZ_DUO_BACKEND_HOST});
  }

  my $client_assertion = Mojo::JWT->new(
    claims    => $jwt_args,
    secret    => $self->client_secret,
    algorithm => 'HS512'
  )->encode;

  my $all_args = {
    'grant_type'            => 'authorization_code',
    'code'                  => $duo_code,
    'redirect_uri'          => $self->redirect_uri,
    'client_id'             => $self->client_id,
    'client_assertion_type' => CLIENT_ASSERT_TYPE,
    'client_assertion'      => $client_assertion,
  };

  WARN(dumper $all_args);

  my $ua = mojo_user_agent();
  my $result;
  try {
    $result = mojo_user_agent()->post($token_uri, form => $all_args)->result;
  }
  catch {
    WARN("duo_client_error: $_ " . $result->message);
    ThrowCodeError('duo_client_error', {reason => ERR_TOKEN_ERROR});
  };

  if (!$result->is_success) {
    WARN('duo_client_error: ' . $result->message);
    ThrowCodeError('duo_client_error', {reason => ERR_TOKEN_ERROR});
  }

  my $decoded_token;
  try {
    $decoded_token
      = Mojo::JWT->new(secret => $self->client_secret, algorithm => 'HS512')
      ->decode($result->json->{id_token});
  }
  catch {
    my $error = $_;
    WARN("duo_client_error: $error");
    ThrowCodeError('duo_client_error', {reason => ERR_TOKEN_ERROR});
  };

  if (!exists $decoded_token->{preferred_username}
    || $decoded_token->{preferred_username} ne $username)
  {
    ThrowUserError('duo_user_error', {reason => ERR_USERNAME});
  }

  return $decoded_token;
}

1;
