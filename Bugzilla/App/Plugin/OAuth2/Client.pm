# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::OAuth2::Client;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin::OAuth2';

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Hook;

sub register {
  my ($self, $app) = @_;
  my $params = Bugzilla->params;

  return unless $params->{oauth2_client_enabled};

  # Get information about user from OAuth2 provider
  $app->helper(
    'oauth2.userinfo' => sub {
      my ($c, $access_token) = @_;
      my $ua     = Mojo::UserAgent->new;
      my $result = $ua->get(
        Bugzilla->params->{'oauth2_client_userinfo_url'},
        {Authorization => 'Bearer ' . $access_token},
      )->result;
      WARN($result->message) if !$result->is_success;
      return $result->json || {};
    }
  );

  $app->helper(
    'oauth2.redirect_uri' => sub {
      my ($c, $redirect) = @_;
      return Bugzilla->localconfig->urlbase . 'oauth2.cgi?redirect=' . $redirect;
    }
  );

  my $conf = {
    oauth2 => {
      authorize_url => $params->{oauth2_client_authorize_url} . '?response_type=code',
      token_url     => $params->{oauth2_client_access_token_url},
      key           => $params->{oauth2_client_id},
      secret        => $params->{oauth2_client_secret},
      scope         => $params->{oauth2_client_scopes},
    }
  };

  Bugzilla::Hook::process('oauth2_client_register',
    {app => $app, $conf => $conf});

  return $self->SUPER::register($app, $conf);
}

1;
