# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use Cwd qw(realpath);

BEGIN {
  require lib;
  my $dir = realpath(dirname(__FILE__));
  lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}
use Mojolicious::Commands;

$ENV{MOJO_LISTEN} ||= $ENV{PORT} ? "http://*:$ENV{PORT}" : "http://*:8000";

# Start command line interface for application
Mojolicious::Commands->start_app('External::Test::API');

package External::Test::API;
use Mojo::Base 'Mojolicious';

sub startup {
  my ($self) = @_;
  my $r = $self->routes;

  # Mock the IPrepD API violations endpoint
  $r->put(
    '/violations/type/ip/*ip' => sub {
      my $c = shift;
      $c->app->defaults->{last_violation} = $c->req->json;
      $c->render(text => 'OK ', status => 200);
    }
  );
  $r->get(
    '/violations/last' => sub {
      my $c = shift;
      $c->render(json => $c->app->defaults->{last_violation}, status => 200);
    }
  );

  # Webhook endpoints for testing
  $r->post(
    '/webhooks/test/noauth' => sub {
      my $c = shift;
      $c->render(json => {ok => 1}, status => 200);
    }
  );
  $r->post(
    '/webhooks/test/withauth' => sub {
      my $c = shift;
      if ($c->req->headers->header('Authorization') eq
        'Token zQ5TSBzq7tTZMtKYq9K1ZqJMjifKx3cPL7pIGk9Q')
      {
        $c->render(json => {ok => 1}, status => 200);
      }
      else {
        $c->render(json => {ok => 0}, status => 401);
      }
    }
  );

  # Mocked OAuth2 endpoints
  $r->post(
    '/oauth/test/token' => sub {
      my $c = shift;
      $c->render(
        json => {
          access_token  => 'fake_access_token',
          expires_in    => 3600,
          refresh_token => 'fake_refresh_token',
          scope         => 'openid profile email',
          token_type    => 'bearer',
        },
        status => 200
      );
    }
  );
  $r->get(
    '/oauth/test/authorize' => sub {
      my $c   = shift;
      my $url = Mojo::URL->new($c->param('redirect_uri'));
      $url->query->append(code  => 'fake_return_code');
      $url->query->append(state => $c->param('state'));
      $c->render(text => $c->tag('a', href => $url, sub { 'Connect' }));
    }
  );
  $r->get(
    '/oauth/test/userinfo' => sub {
      my $c = shift;
      $c->render(
        json => {
          email          => 'oauth2-user@example.com',
          name           => 'OAuth2 Test User',
          email_verified => 1,
        },
        status => 200
      );
    }
  );

  # Mocked PersonAPI endpoints
  my $person_data = {
    primary_email => {value => 'oauth2-user@mozilla.com'},
    first_name    => {value => 'Mozilla'},
    last_name     => {value => 'IAM User'},
    identities    =>
      {bugzilla_mozilla_org_primary_email => {value => 'oauth2-user@example.com'}},
    access_information => {ldap => {values => {team_moco => 1}}}
  };
  $r->get(
    '/person/test/v2/user/primary_email/*email' => sub {
      shift->render(json => $person_data, status => 200);
    }
  );
  $r->get(
    '/person/test/v2/user/user_id/*id' => sub {
      shift->render(json => $person_data, status => 200);
    }
  );

  # Endpoint used for getting version details of Mozilla products
  my $product_details = {
    'FIREFOX_DEVEDITION'                    => '111.0b2',
    'FIREFOX_ESR'                           => '102.8.0esr',
    'FIREFOX_NIGHTLY'                       => '111.0a1',
    'LATEST_FIREFOX_DEVEL_VERSION'          => '110.0b2',
    'LATEST_FIREFOX_RELEASED_DEVEL_VERSION' => '110.0b2',
    'LATEST_FIREFOX_VERSION'                => '109.0',
  };
  $r->get(
    '/product_details/firefox_versions.json' => sub {
      shift->render(json => $product_details, status => 200);
    }
  );
}

1;
