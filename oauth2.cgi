#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Logging;
use Bugzilla::Token qw(check_hash_token delete_token);

use Mojo::JWT;
use Mojo::UserAgent;
use Try::Tiny;

my $cache = Bugzilla->request_cache;
my $cgi   = Bugzilla->cgi;
my $c     = $cache->{mojo_controller};

# GET requests come from OAuth2 provider,
# with this script acting as the OAuth2 callback.

# Verify state value is valid
my $token = $cgi->param('state');
check_hash_token($token, ['oauth2']);
delete_token($token);

# Get access token from OAuth2 provider;
my $resp = $c->oauth2->get_token();

# Store user information for use by OAuth2 login info getter
my $userinfo;
if ($resp && $resp->{id_token}) {
  try {
    my $jwks
      = Mojo::UserAgent->new->get(
      Bugzilla->params->{oauth2_client_domain} . '/.well-known/jwks.json')
      ->result->json('/keys');
    $userinfo = Mojo::JWT->new(jwks => $jwks)->decode($resp->{id_token});
  }
  catch {
    WARN($_);
  };
}

if (!$userinfo && $resp && $resp->{access_token}) {
  $userinfo = $c->oauth2->userinfo($resp->{access_token});
}

$userinfo || ThrowUserError('oauth2_userinfo_error');

Bugzilla::Hook::process('oauth2_client_pre_login', {userinfo => $userinfo});

$cache->{oauth2_client_userinfo} = $userinfo;

my $user = Bugzilla->login(LOGIN_REQUIRED);

Bugzilla::Hook::process('oauth2_client_post_login',
  {user => $user, userinfo => $userinfo});

# Go back where we came from
$cgi->redirect($cgi->param('redirect'));
