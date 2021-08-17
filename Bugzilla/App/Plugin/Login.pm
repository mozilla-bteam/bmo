# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::Login;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Bugzilla::Constants;
use Bugzilla::User::APIKey;
use Bugzilla::Util qw(with_writable_database);

use Mojo::Util qw(secure_compare);

sub register {
  my ($self, $app, $conf) = @_;

  $app->helper(
    'bugzilla.login_redirect_if_required' => sub {
      my ($c, $type) = @_;

      if ($type == LOGIN_REQUIRED) {
        $c->redirect_to(Bugzilla->localconfig->basepath . 'login');
        return undef;
      }
      else {
        return Bugzilla->user;
      }
    }
  );

  $app->helper(
    'bugzilla.login' => sub {
      my ($c, $type) = @_;
      $type //= LOGIN_NORMAL;
      my $headers = $c->tx->req->headers;
      my $user_id = 0;

      return Bugzilla->user if Bugzilla->user->id;

      $type = LOGIN_REQUIRED
        if $c->param('GoAheadAndLogIn') || Bugzilla->params->{requirelogin};

      # Allow templates to know that we're in a page that always requires
      # login.
      if ($type == LOGIN_REQUIRED) {
        Bugzilla->request_cache->{page_requires_login} = 1;
      }

      # Try cookies first if we are using the web UI
      if (Bugzilla->usage_mode != USAGE_MODE_REST) {
        my $login_cookie  = $c->cookie("Bugzilla_logincookie");
        my $login_user_id = $c->cookie("Bugzilla_login");

        if ($login_cookie && $login_user_id) {
          my $db_cookie
            = Bugzilla->dbh->selectrow_array(
            'SELECT cookie FROM logincookies WHERE cookie = ? AND userid = ?',
            undef, ($login_cookie, $login_user_id));

          if (defined $db_cookie && secure_compare($login_cookie, $db_cookie)) {
            $user_id = $login_user_id;

            # If we logged in successfully, then update the lastused
            # time on the login cookie
            with_writable_database {
              Bugzilla->dbh->do(
                q{ UPDATE logincookies SET lastused = NOW() WHERE cookie = ? },
                undef, $login_cookie);
            };
          }
        }
      }

      # Next check for an API key in the header
      if (Bugzilla->usage_mode == USAGE_MODE_REST) {
        if (my $api_key_text = $headers->header('x-bugzilla-api-key')) {
          if (my $api_key = Bugzilla::User::APIKey->new({name => $api_key_text})) {
            my $remote_ip = $c->tx->remote_address;
            if (
              (
                   $api_key->sticky
                && $api_key->last_used_ip
                && $api_key->last_used_ip ne $remote_ip
              )
              || $api_key->revoked
              )
            {
              Bugzilla->iprepd_report('api_key');
            }
            else {
              $api_key->update_last_used($remote_ip);
              $user_id = $api_key->user_id;
            }
          }
          else {
            Bugzilla->iprepd_report('api_key');
          }
        }

        # Also allow use of OAuth2 bearer tokens to access the API
        if ($headers->header('Authorization')) {
          my $user = $c->bugzilla->oauth('api:modify');
          if ($user && $user->id) {
            $user_id = $user->id;
          }
          else {
            Bugzilla->iprepd_report('api_key');
          }
        }
      }

      if ($user_id) {
        my $user = Bugzilla::User->check({id => $user_id, cache => 1});
        Bugzilla->set_user($user);
        return $user;
      }

      return $c->bugzilla->login_redirect_if_required($type);
    }
  );
}

1;
