# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM::Util;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;
use Bugzilla::Token;
use Bugzilla::User;
use Bugzilla::Util qw(url_quote);

use Mojo::JWT;
use Mojo::UserAgent;
use Try::Tiny;

use base qw(Exporter);
our @EXPORT_OK = qw(
  add_staff_member
  get_access_token
  get_profile_by_email
  get_profile_by_id
  remove_staff_member
  user_agent
  verify_token
);

sub add_staff_member {
  my $params       = shift;
  my $bmo_email    = $params->{bmo_email};
  my $iam_username = $params->{iam_username};
  my $real_name    = $params->{real_name};
  my $is_staff     = $params->{is_staff};

  # We need to make the below changes as an empowered user
  my $empowered_user
    = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

  # If user does not have an account, create one
  my $user = Bugzilla::User->new({name => $bmo_email});

  return 0 if !$user;

  # Update iam_username value with email from Mozilla IAM
  # Also set password to * to disallow local login.
  if ($user->iam_username ne $iam_username) {
    $user->set_iam_username($iam_username);
    $user->set_password('*') if $user->cryptpassword ne '*';
    $user->set_mfa('');
  }

  # Update group permissions if user is staff
  if (!$user->in_group('mozilla-employee-confidential') && $is_staff) {
    $user->set_groups({add => ['mozilla-employee-confidential']});
  }

  $user->update({keep_session => 1, keep_tokens => 1});    # Do not log user out

  return 1;
}

sub remove_staff_member {
  my $params = shift;

  # We need to make the below changes as an empowered user
  my $empowered_user
    = Bugzilla->set_user(Bugzilla::User->super_user, scope_guard => 1);

  my $user = $params->{user};
  if (!$user) {
    my $user_id
      = Bugzilla->dbh->selectrow_array(
      'SELECT user_id FROM profiles_iam WHERE iam_username = ?',
      undef, $params->{iam_username});
    $user = Bugzilla::User->new($user_id);
  }

  if ($user && $user->iam_username) {
    $user->set_iam_username('');
    $user->set_password('*') if $user->cryptpassword ne '*';
    $user->set_mfa('');

    if ($user->in_group('mozilla-employee-confidential')) {
      $user->set_groups({remove => ['mozilla-employee-confidential']});
    }

    # Issue email allowing user to set their password
    Bugzilla::Token::IssuePasswordToken($user);

    $user->update();    # Do not keep_session so user is logged out
  }

  return 1;
}

sub get_access_token {
  my $params = Bugzilla->params;

  # Return fake token for CI tests
  return 'fake_access_token' if $ENV{CI};

  my $access_token;
  try {
    $access_token = user_agent()->post(
      $params->{oauth2_client_token_url} => {'Content-Type' => 'application/json'} =>
        json                             => {
        client_id     => $params->{mozilla_iam_person_api_client_id},
        client_secret => $params->{mozilla_iam_person_api_client_secret},
        audience      => 'api.sso.mozilla.com',
        grant_type    => 'client_credentials',
        },
    )->result->json('/access_token');
  }
  catch {
    WARN($_);
    ThrowCodeError('mozilla_iam_access_token_error');
  };

  return $access_token;
}

sub get_profile_by_email {
  my ($email, $access_token) = @_;
  return _get_profile('/v2/user/primary_email/' . url_quote($email),
    $access_token);
}

sub get_profile_by_id {
  my ($id, $access_token) = @_;
  return _get_profile('/v2/user/user_id/' . url_quote($id), $access_token);
}

sub _get_profile {
  my ($query_path, $access_token) = @_;

  # For CI, return test data that mocks the PersonAPI
  if ( $ENV{CI}
    && $ENV{BZ_TEST_OAUTH2_NORMAL_USER}
    && $ENV{BZ_TEST_OAUTH2_MOZILLA_USER})
  {
    return {
      bmo_email    => $ENV{BZ_TEST_OAUTH2_NORMAL_USER},
      first_name   => 'Mozilla',
      last_name    => 'IAM User',
      iam_username => $ENV{BZ_TEST_OAUTH2_MOZILLA_USER},
      is_staff     => 1,
    };
  }

  $access_token ||= get_access_token();
  return {} if !$access_token;

  my $url = Bugzilla->params->{mozilla_iam_person_api_uri} . $query_path;

  my $data = {};
  try {
    $data = user_agent()->get($url => {'Authorization' => "Bearer ${access_token}"})
      ->result->json;
  }
  catch {
    WARN($_);
    ThrowCodeError('mozilla_iam_get_profile_error');
  };

  return {} if !$data;

  return {
    is_staff     => $data->{staff_information}->{staff}->{value},
    iam_username => $data->{primary_email}->{value},
    bmo_email => $data->{identities}->{bugzilla_mozilla_org_primary_email}->{value},
    first_name => $data->{first_name}->{value},
    last_name  => $data->{last_name}->{value},
  };
}

sub user_agent {
  my $ua = Mojo::UserAgent->new(
    request_timeout     => 5,
    connect_timeout     => 5,
    inactivity_timesout => 30
  );
  if (my $proxy = Bugzilla->params->{proxy_url}) {
    $ua->proxy->http($proxy)->https($proxy);
  }
  else {
    $ua->proxy->detect();
  }
  $ua->transactor->name('Bugzilla');
  return $ua;
}

sub verify_token {
  my $authorization_header = shift;
  my ($bearer, $token) = split /\s+/, $authorization_header;

  return 0 if $bearer !~ /bearer/i || !$token;

  try {
    my $jwks
      = user_agent()
      ->get(Bugzilla->params->{oauth2_client_domain} . '/.well-known/jwks.json')
      ->result->json('/keys');
    $token = Mojo::JWT->new(jwks => $jwks)->decode($token);
  }
  catch {
    WARN($_);
    ThrowCodeError('mozilla_iam_verify_token_error');
  };

  return 1;
}

1;
