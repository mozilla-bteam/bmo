# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::OAuth2::Client;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Hook;
use Bugzilla::Util qw(mojo_user_agent);

use Mojo::Parameters;
use Mojo::URL;
use Try::Tiny;

sub register {
  my ($self, $app) = @_;
  my $params = Bugzilla->params;

  return unless $params->{oauth2_client_enabled};

  $app->helper(
    'oauth2.auth_url' => sub {
      my ($c, $type, $args) = @_;
      my $params = Bugzilla->params;

      $args->{scope}        ||= $params->{oauth2_client_scopes};
      $args->{redirect_uri} ||= $c->url_for->to_abs->to_string;

      my $authorize_url = Mojo::URL->new($params->{oauth2_client_authorize_url});
      $authorize_url->query->append(
        client_id     => $params->{oauth2_client_id},
        redirect_uri  => $args->{redirect_uri},
        response_type => 'code',
      );
      if (defined $args->{scope}) {
        $authorize_url->query->append(scope => $args->{scope});
      }
      if (defined $args->{state}) {
        $authorize_url->query->append(state => $args->{state});
      }

      return $authorize_url;
    }
  );

  $app->helper(
    'oauth2.get_token' => sub {
      my ($c, $args) = @_;
      my $params = Bugzilla->params;

      if ($ENV{CI}) {
        return {
          access_token  => 'fake_access_token',
          expires_in    => 3600,
          refresh_token => 'fake_refresh_token',
          scope         => 'openid profile email',
          token_type    => 'bearer',
        };
      }

      my $data = {
        client_id     => $params->{oauth2_client_id},
        client_secret => $params->{oauth2_client_secret},
        code          => scalar($c->param('code')),
        grant_type    => 'authorization_code',
        redirect_uri  => $c->url_for->to_abs->to_string,
      };

      my $token_url = Mojo::URL->new($params->{oauth2_client_token_url});
      $token_url = $token_url->to_abs;

      try {
        my $tx = mojo_user_agent()->post($token_url, form => $data);
        die $tx->result->message if !$tx->result->is_success;
        return $tx->res->headers->content_type =~ /^application\/json/
          ? $tx->res->json
          : Mojo::Parameters->new($tx->res->body)->to_hash;
      }
      catch {
        WARN("ERROR: Could not get oauth2 token: $_");
        return {};
      };
    }
  );

  # Get information about user from OAuth2 provider
  $app->helper(
    'oauth2.userinfo' => sub {
      my ($c, $access_token) = @_;
      my $params = Bugzilla->params;

      if ($ENV{CI} && $ENV{BZ_TEST_OAUTH2_NORMAL_USER}) {
        return {
          email          => $ENV{BZ_TEST_OAUTH2_NORMAL_USER},
          name           => 'OAuth2 Test User',
          email_verified => 1,
        };
      }

      try {
        my $tx = mojo_user_agent()->get(
          $params->{'oauth2_client_userinfo_url'},
          {Authorization => 'Bearer ' . $access_token},
        );
        die $tx->result->message if !$tx->result->is_success;
        return $tx->result->json || {};
      }
      catch {
        WARN("ERROR: Could not get userinfo: $_");
        return {};
      };
    }
  );

  $app->helper(
    'oauth2.redirect_uri' => sub {
      my ($c, $redirect) = @_;
      return Bugzilla->localconfig->urlbase . 'oauth2.cgi?redirect=' . $redirect;
    }
  );

  # Add special routes for CI testing that mocks a providers login
  if ($ENV{CI}) {
    $app->routes->get(
      '/oauth/test/authorize' => sub {
        my $c   = shift;
        my $url = Mojo::URL->new($c->param('redirect_uri'));
        $url->query->append(code  => 'fake_return_code');
        $url->query->append(state => $c->param('state'));
        $c->render(text => $c->tag('a', href => $url, sub {'Connect'}));
      },
    );
  }

  Bugzilla::Hook::process('oauth2_client_register', {app => $app});
}

1;
