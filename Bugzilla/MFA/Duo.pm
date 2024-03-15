# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA::Duo;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::MFA';

use Bugzilla::DuoClient;

sub can_verify_inline {
  return 0;
}

sub enroll {
  my ($self, $params) = @_;
  $self->property_set('user', $params->{username});
}

sub prompt {
  my ($self, $vars, $token) = @_;
  my $cgi    = Bugzilla->cgi;
  my $params = Bugzilla->params;

  my $duo = Bugzilla::DuoClient->new(
    host          => $params->{duo_host},
    client_id     => $params->{duo_client_id},
    client_secret => $params->{duo_client_secret},
  );

  # Make sure Duo Security service is available
  $duo->health_check();

  # Set cookie with token to verify form submitted
  # from Bugzilla and not a different domain.
  $cgi->send_cookie(
    -name     => 'mfa_verification_token',
    -value    => $token,
    -httponly => 1,
  );

  my $username     = $self->property_get('user');
  my $redirect_uri = $duo->create_auth_url($username, $token);

  print $cgi->redirect($redirect_uri);
}

# Always return 0 (failure) in case check() for Duo called just to be safe
# This should now happen.
sub check {
  return 0;
}

1;
