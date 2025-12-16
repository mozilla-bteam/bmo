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

use File::Basename        qw(dirname);
use File::Spec::Functions qw(catdir);
use Cwd                   qw(realpath);

BEGIN {
  require lib;
  my $dir = realpath(dirname(__FILE__));
  lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}
use Mojolicious::Commands;

$ENV{MOJO_LISTEN} ||= $ENV{PORT} ? "http://*:$ENV{PORT}" : 'http://*:8000';

# Start command line interface for application
Mojolicious::Commands->start_app('External::Test::API');

package External::Test::API;
use Mojo::Base 'Mojolicious';

use Mojo::JSON qw(decode_json);
use Mojo::JWT;
use Mojo::Log;
use Mojo::Util qw(dumper);

use Bugzilla::Util qw(generate_random_password);

# Place to hold data between API calls
my $cache = {};

sub startup {
  my ($self) = @_;
  my $r = $self->routes;

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

  # Endpoint that just stores the JSON payload for later retrieval
  $r->post(
    '/webhooks/store_payload' => sub {
      my $c    = shift;
      my $data = decode_json($c->req->body);
      $cache->{webhook_last_payload} = $data;
      return $c->render(json => {ok => 1}, status => 200);
    }
  );

  # Endpoint to retrieve the last stored webhook payload
  $r->get(
    '/webhooks/last_payload' => sub {
      my $c    = shift;
      my $data = $cache->{webhook_last_payload};
      if (!$data) {
        return $c->render(
          json   => {error => 1, message => 'No payload stored'},
          status => 404
        );
      }
      return $c->render(json => $data, status => 200);
    }
  );

  # Mocked OAuth2 endpoints
  # $r->post(
  #   '/oauth/test/token' => sub {
  #     my $c = shift;
  #     $c->render(
  #       json => {
  #         access_token  => 'fake_access_token',
  #         expires_in    => 3600,
  #         refresh_token => 'fake_refresh_token',
  #         scope         => 'openid profile email',
  #         token_type    => 'bearer',
  #       },
  #       status => 200
  #     );
  #   }
  # );
  # $r->get(
  #   '/oauth/test/authorize' => sub {
  #     my $c   = shift;
  #     my $url = Mojo::URL->new($c->param('redirect_uri'));
  #     $url->query->append(code  => 'fake_return_code');
  #     $url->query->append(state => $c->param('state'));
  #     $c->render(text => $c->tag('a', href => $url, sub {'Connect'}));
  #   }
  # );
  # $r->get(
  #   '/oauth/test/userinfo' => sub {
  #     my $c = shift;
  #     $c->render(
  #       json => {
  #         email          => 'oauth2-user@example.com',
  #         name           => 'OAuth2 Test User',
  #         email_verified => 1,
  #       },
  #       status => 200
  #     );
  #   }
  # );

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

  # Duo Security Mocked endpoints
  $r->post(
    '/oauth/v1/health_check' => sub {
      shift->render(json => {stat => 'OK'}, status => 200);
    }
  );
  $r->get(
    '/oauth/v1/authorize' => sub {
      my $c = shift;

      my $client_id = $c->param('client_id');
      my $request   = $c->param('request');

      # Load selenium config file to get the client secret, etc.
      my $conf_file = '/app/qa/config/selenium_test.conf';
      my $config = do($conf_file) or die "can't read configuration '$conf_file': $!";
      my $client_secret = $config->{duo_client_secret};

      my $decoded_payload
        = Mojo::JWT->new(secret => $client_secret, algorithm => 'HS512')
        ->decode($request);

      # Save username for later call for token exchange
      my $duo_code  = generate_random_password();
      my $duo_uname = $decoded_payload->{duo_uname};
      $cache->{$duo_code} = $duo_uname;

      my $url = Mojo::URL->new($decoded_payload->{redirect_uri});
      $url->query->append(duo_code => $duo_code, state => $decoded_payload->{state});
      $c->render(text => $c->tag('a', href => $url, sub {'Redirect Back'}));
    }
  );
  $r->post(
    '/oauth/v1/token' => sub {
      my $c = shift;

      my $duo_uname = $cache->{$c->param('code')};

      # Load selenium config file to get the client secret, etc.
      my $conf_file = '/app/qa/config/selenium_test.conf';
      my $config = do($conf_file) or die "can't read configuration '$conf_file': $!";
      my $client_secret = $config->{duo_client_secret};

      my $id_token = Mojo::JWT->new(
        claims    => {preferred_username => $duo_uname},
        secret    => $client_secret,
        algorithm => 'HS512'
      )->encode;

      $c->render(json => {id_token => $id_token}, status => 200);
    }
  );

  # Recorded Future Identity API Mocked endpoints
  # This simulates the Recorded Future API for testing the recorded_future.pl script
  $r->get(
    '/recordedfuture/identity/search' => sub {
      my $c = shift;

      # Check for Bearer token auth
      my $auth = $c->req->headers->authorization;
      unless ($auth && $auth eq 'Bearer test_api_key') {
        return $c->render(
          json   => {error => "Unauthorized"},
          status => 401
        );
      }

      # Get query parameters
      my $domain                = $c->param('domain');
      my $latest_downloaded_gte = $c->param('latest_downloaded_gte');
      my $offset                = $c->param('offset');

      # Mock data - 3 identities with compromised credentials
      # test1@example.com - password: "password123" (should match)
      # test2@example.com - password: "different456" (won't match)
      # test3@example.com - no cleartext password available
      my @all_mock_identities = (
        {
          identity => {
            subjects => ['test1@example.com']
          },
          credentials => [
            {
              subject         => 'test1@example.com',
              exposed_secret  => {
                clear_text_value => 'correctpassword123!',
                clear_text_hint  => 'co',
              },
              latest_downloaded => '2025-12-08',
              first_downloaded  => '2025-12-01',
              dumps             => [
                {name => 'TestBreach2025', type => 'dump'}
              ],
            }
          ],
          count => 1
        },
        {
          identity => {
            subjects => ['test2@example.com']
          },
          credentials => [
            {
              subject         => 'test2@example.com',
              exposed_secret  => {
                clear_text_value => 'different456!',
                clear_text_hint  => 'di',
              },
              latest_downloaded => '2025-12-08',
              first_downloaded  => '2025-12-01',
              dumps             => [
                {name => 'AnotherBreach2025', type => 'dump'}
              ],
            }
          ],
          count => 1
        },
        {
          identity => {
            subjects => ['test3@example.com']
          },
          credentials => [
            {
              subject         => 'test3@example.com',
              exposed_secret  => {
                # No clear_text_value - only hashed
                clear_text_hint => 'xx',
              },
              latest_downloaded => '2025-12-08',
              first_downloaded  => '2025-12-01',
              dumps             => [
                {name => 'HashedBreach2025', type => 'dump'}
              ],
            }
          ],
          count => 1
        },
      );

      # Filter by domain if provided
      if ($domain && $domain ne 'bugzilla.mozilla.org') {
        return $c->render(
          json => {
            count      => 0,
            identities => [],
          },
          status => 200
        );
      }

      # Simple pagination: split into pages of 2 items each for testing
      my $page_size = 2;
      my $start_idx = 0;

      if ($offset) {
        if ($offset eq 'page2') {
          $start_idx = 2;
        }
        elsif ($offset eq 'page3') {
          $start_idx = 4;
        }
      }

      my $end_idx = $start_idx + $page_size - 1;
      $end_idx = $#all_mock_identities if $end_idx > $#all_mock_identities;

      my @page_identities
        = $start_idx <= $#all_mock_identities
        ? @all_mock_identities[$start_idx .. $end_idx]
        : ();

      my $next_offset = undef;
      if ($end_idx < $#all_mock_identities) {
        $next_offset = 'page' . ($start_idx / $page_size + 2);
      }

      my $response = {
        count      => scalar(@all_mock_identities),
        identities => \@page_identities,
      };
      $response->{next_offset} = $next_offset if $next_offset;

      return $c->render(json => $response, status => 200);
    }
  );
}

1;
