# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Auth::Login::APIKey;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Auth::Login);

use Bugzilla::Constants;
use Bugzilla::User::APIKey;
use Bugzilla::Util;
use Bugzilla::Error;

use constant requires_persistence  => 0;
use constant requires_verification => 0;
use constant can_login             => 0;
use constant can_logout            => 0;
use constant auth_method           => 'APIKey';

use fields qw(app_id);

sub set_app_id {
  my ($self, $app_id) = @_;
  $self->{app_id} = $app_id;
}

sub app_id {
  my ($self) = @_;
  return $self->{app_id};
}

# This method is only available to web services. An API key can never
# be used to authenticate a Web request.
sub get_login_info {
  my ($self) = @_;
  my $cgi    = Bugzilla->cgi;
  my $params = Bugzilla->input_params;
  my ($user_id, $login_cookie);

  return {failure => AUTH_NODATA} if !i_am_webservice();

  # First check for an API key in the header or passed as query params
  my $api_key_text = trim($cgi->http('X_BUGZILLA_API_KEY'));

  # Legacy API code looks for the header and if present puts the value
  # into the input params as well. If exists, we need to delete it here
  # as the extra param can crash other functions such as Bugzilla::Bug::create().
  if ($params->{'Bugzilla_api_key'}) {
    $api_key_text = trim(delete $params->{Bugzilla_api_key});
  }

  if ($api_key_text) {
    my $api_key   = Bugzilla::User::APIKey->new({name => $api_key_text});
    my $remote_ip = remote_ip();

    if (!$api_key or $api_key->api_key ne $api_key_text) {

      # The second part checks the correct capitalization. Silly MySQL
      Bugzilla->iprepd_report('api_key', $remote_ip);
      ThrowUserError("api_key_not_valid");
    }
    elsif ($api_key->sticky
      && $api_key->last_used_ip
      && $api_key->last_used_ip ne $remote_ip)
    {
      Bugzilla->iprepd_report('api_key');
      ThrowUserError("api_key_not_valid");
    }
    elsif ($api_key->revoked) {
      ThrowUserError('api_key_revoked');
    }

    $api_key->update_last_used($remote_ip);
    $self->set_app_id($api_key->app_id);

    return {user_id => $api_key->user_id};
  }

  # Also allow use of OAuth2 bearer tokens to access the API
  if (trim($cgi->http('Authorization'))) {
    my $C    = Bugzilla->request_cache->{mojo_controller};
    my $user = $C->bugzilla->oauth('api:modify');
    if ($user && $user->id) {
      return {user_id => $user->id};
    }
  }

  return {failure => AUTH_NODATA};
}

1;
