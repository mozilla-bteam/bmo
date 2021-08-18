#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}         = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE}     = 1;
  $ENV{BUGZILLA_ALLOW_INSECURE_HTTP} = 1;
}

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla::Test::Util qw(create_user create_oauth_client);

use Test2::V0;
use Test::Mojo;

my $oauth_login    = 'oauth@mozilla.bugs';
my $oauth_password = 'password123456789!';
my $stash          = {};

# Create user to use as OAuth2 resource owner
my $oauth_user = create_user($oauth_login, $oauth_password);

# Create a new standard OAuth2 client used for testing
my $oauth_client = create_oauth_client('Shiny New OAuth Client', ['user:read']);
ok $oauth_client->{client_id},
  'New client id (' . $oauth_client->{client_id} . ')';
ok $oauth_client->{secret},
  'New client secret (' . $oauth_client->{secret} . ')';

# Create another OAuth2 client used for API testing
my $oauth_api_client = create_oauth_client('Another Shiny New OAuth Client',
  ['user:read', 'api:modify']);
ok $oauth_api_client->{client_id},
  'New api client id (' . $oauth_api_client->{client_id} . ')';
ok $oauth_client->{secret},
  'New api client secret (' . $oauth_api_client->{secret} . ')';

my $t = Test::Mojo->new('Bugzilla::App');

# Allow 1 redirect max
$t->ua->max_redirects(1);

# Custom routes and hooks required to support running the tests
_setup_routes($t->app->routes);
$t->app->hook(after_dispatch => sub { $stash = shift->stash });

# Make sure we can do a normal login and access our profile data
my $access_data = login(
  t        => $t,
  client   => $oauth_client,
  user     => $oauth_user,
  login    => $oauth_login,
  password => $oauth_password
);

$t->get_ok('/api/user/profile' =>
    {Authorization => 'Bearer ' . $access_data->{access_token}})->status_is(200)
  ->json_is('/login' => $oauth_user->email);

# Trying to access using an OAuth2 user without 'api:modify' scope on their
# account should also fail.
$t->get_ok("/rest/user/"
    . $oauth_user->id =>
    {Authorization => 'Bearer ' . $access_data->{access_token}})->status_is(401);

# Login to the API enabled OAuth2 client
$access_data = login(
  t        => $t,
  client   => $oauth_api_client,
  user     => $oauth_user,
  login    => $oauth_login,
  password => $oauth_password

);

# We should also be able to call any legacy REST API method
# using the OAuth2 access token in the header.
# /rest/user/<id> is a good example as it requires login
$t->get_ok("/rest/user/"
    . $oauth_user->id =>
    {Authorization => 'Bearer ' . $access_data->{access_token}})->status_is(200)
  ->json_is('/users/0/email' => $oauth_user->email);

# Try to use /rest/user/<id> without logging in using OAuth2 token
# should result in an access error.
$t->get_ok("/rest/user/" . $oauth_user->id)->status_is(401);

# Pass in garbage as an access-token to ensure that the call fails correctly
$t->get_ok("/rest/user/"
    . $oauth_user->id =>
    {Authorization => 'Bearer 1234567890!@#$%^&*()'})->status_is(401);
$t->get_ok("/rest/user/"
    . $oauth_user->id =>
    {Authorization => 'Bearer '})->status_is(401);
$t->get_ok("/rest/user/"
    . $oauth_user->id =>
    {Authorization => ' '})->status_is(401);

# User profile API call should fail if user is disabled
$oauth_user->set_disabledtext('DISABLED');
$oauth_user->update();
$t->get_ok('/api/user/profile' =>
    {Authorization => 'Bearer ' . $access_data->{access_token}})->status_is(401);

done_testing;

sub login {
  my (%args) = @_;
  my ($t, $client, $user, $login, $password)
    = @args{qw/t client user login password/};
  my $referer = Bugzilla->localconfig->urlbase;

  # Logout current user
  Bugzilla->logout_user($user);

 # User should be logged out so /oauth/authorize should redirect to a login screen
  $t->get_ok(
    '/oauth/authorize' => {Referer => $referer} => form => {
      client_id     => $client->{client_id},
      response_type => 'code',
      state         => 'state',
      scope         => 'user:read',
      redirect_uri  => '/oauth/redirect'
    }
  )->status_is(200)
    ->element_exists('div.login-form input[name=Bugzilla_login_token]')
    ->text_is('html head title' => 'Log in to Bugzilla');

  # Login the user in using the resource owner username and password
  # Once logged in, we should automatically be redirected to the confirm
  # scopes page.
  $t->post_ok(
    '/login' => {Referer => $referer} => form => {
      Bugzilla_login    => $login,
      Bugzilla_password => $password,
      GoAheadAndLogIn   => 1,
      client_id         => $client->{client_id},
      response_type     => 'code',
      state             => 'state',
      scope             => join(' ', @{$client->{scopes}}),
      redirect_uri      => '/oauth/redirect'
    }
  )->status_is(200)->text_is('title' => 'Request for access to your account');

  # Get the csrf token to allow submitting the scope confirmation form
  my $csrf_token = $t->tx->res->dom->at('input[name=token]')->val;
  ok $csrf_token, "Get csrf token ($csrf_token)";

  # Redirect and get the auth code needed for obtaining an access token
  # Once we accept the scopes requested, we should get redirected to the
  # URI specified in the redirect_uri value. In this case a simple text page.
  $t->get_ok(
    '/oauth/authorize' => {Referer => $referer} => form => {
      "oauth_confirm_" . $client->{client_id} => 1,
      token                                   => $csrf_token,
      client_id                               => $client->{client_id},
      response_type                           => 'code',
      state                                   => 'state',
      scope                                   => join(' ', @{$client->{scopes}}),
      redirect_uri                            => '/oauth/redirect'
    }
  )->status_is(200)->content_is('Redirect Success!');

  # The redirect page (normally an external site associated with the
  # OAuth2 client) should verify the state token and also get a temporary
  # auth code that will be used to request an access token.
  my $state = $stash->{state};
  ok $state eq 'state', "State was returned correctly";
  my $auth_code = $stash->{auth_code};
  ok $auth_code, "Get auth code ($auth_code)";

  # Contact the OAuth2 server using the auth code to obtain an access token
  # This happens as a backend POST the the server and is not visible to the
  # end user.
  $t->post_ok(
    '/oauth/access_token' => {Referer => $referer} => form => {
      client_id     => $client->{client_id},
      client_secret => $client->{secret},
      code          => $auth_code,
      grant_type    => 'authorization_code',
      redirect_uri  => '/oauth/redirect',
    }
  )->status_is(200)->json_has('/access_token', 'Has access token')
    ->json_has('/refresh_token', 'Has refresh token')
    ->json_has('/token_type',    'Has token type');

  my $access_data = $t->tx->res->json;

  # Should get an error if we try to re-use the same auth code again
  $t->post_ok(
    '/oauth/access_token' => {Referer => $referer} => form => {
      client_id     => $client->{client_id},
      client_secret => $client->{secret},
      code          => $auth_code,
      grant_type    => 'authorization_code',
      redirect_uri  => '/oauth/redirect',
    }
  )->status_is(400)->json_is('/error' => 'invalid_grant');

  return $access_data;
}

sub _setup_routes {
  my $r = shift;

  # Add /oauth/redirect route for checking final redirection
  $r->get(
    '/oauth/redirect' => sub {
      my $c = shift;
      $c->stash(state => $c->param('state'), auth_code => $c->param('code'));
      $c->render(status => 200, text => 'Redirect Success!');
      return;
    }
  );
}

