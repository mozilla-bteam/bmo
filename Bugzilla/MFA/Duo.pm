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

use Bugzilla::DuoAPI;
use Bugzilla::DuoWeb;
use Bugzilla::Error;
use Bugzilla::Util qw(remote_ip);

sub can_verify_inline {
  return 0;
}

sub enroll {
  my ($self, $params) = @_;

  # verify that the user is enrolled with duo
  my $client = Bugzilla::DuoAPI->new(
    Bugzilla->params->{duo_ikey},
    Bugzilla->params->{duo_skey},
    Bugzilla->params->{duo_host}
  );
  my $response = $client->json_api_call('POST', '/auth/v2/preauth',
    {username => $params->{username}});

  # not enrolled - show a nice error page instead of just throwing
  unless ($response->{result} eq 'auth' || $response->{result} eq 'allow') {
    print Bugzilla->cgi->header();
    my $template = Bugzilla->template;
    $template->process('mfa/duo/not_enrolled.html.tmpl',
      {email => $params->{username}})
      || ThrowTemplateError($template->error());
    exit;
  }

  $self->property_set('user', $params->{username});
}

sub prompt {
  my ($self, $vars, $token) = @_;
  my $cgi      = Bugzilla->cgi;
  my $template = Bugzilla->template;

  $vars->{sig_request} = Bugzilla::DuoWeb::sign_request(
    Bugzilla->params->{duo_ikey}, Bugzilla->params->{duo_skey},
    Bugzilla->params->{duo_akey}, $self->property_get('user'),
  );

  # Set cookie with token to verify form submitted
  # from Bugzilla and not a different domain.
  $cgi->send_cookie(
    -name     => 'mfa_verification_token',
    -value    => $token,
    -httponly => 1,
  );

  print $cgi->header();
  $template->process('mfa/duo/verify.html.tmpl', $vars)
    || ThrowTemplateError($template->error());
}

sub check {
  my ($self, $params) = @_;

  return
    if Bugzilla::DuoWeb::verify_response(
    Bugzilla->params->{duo_ikey}, Bugzilla->params->{duo_skey},
    Bugzilla->params->{duo_akey}, $params->{sig_response}
    );

  Bugzilla->iprepd_report('bmo.mfa_mismatch', remote_ip());
  Bugzilla->check_rate_limit('mfa_mismatch', $self->{user}->id);
  ThrowUserError('mfa_bad_code');
}

1;
