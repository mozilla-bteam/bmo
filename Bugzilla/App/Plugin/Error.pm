# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Plugin::Error;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::WebService::Constants;

sub register {
  my ($self, $app) = @_;
  $app->helper('code_error' => sub { _render_error('code', @_); });
  $app->helper('user_error' => sub { _render_error('user', @_); });
}

sub _render_error {
  my ($type, $c, $error, $vars) = @_;
  my $logfunc = _make_logfunc(ucfirst($type));

  # Errors displayed in a web page
  if (Bugzilla->error_mode == ERROR_MODE_MOJO
    || Bugzilla->error_mode == ERROR_MODE_WEBPAGE)
  {
    $logfunc->("webpage error: $error");

    $c->render(
      handler  => 'bugzilla',
      template => "global/$type-error",
      format   => 'html',
      error    => $error,
      %{$vars}
    );
  }

  # Errors returned in an API request
  elsif (Bugzilla->error_mode == ERROR_MODE_REST) {
    my %error_map = %{WS_ERROR_CODE()};
    my $code      = $error_map{$error};

    if (!$code) {
      $code = ERROR_UNKNOWN_FATAL     if $type =~ /code/i;
      $code = ERROR_UNKNOWN_TRANSIENT if $type =~ /user/i;
    }

    my %status_code_map = %{REST_STATUS_CODE_MAP()};
    my $status_code     = $status_code_map{$code} || $status_code_map{'_default'};

    $logfunc->("REST error: $error (HTTP $status_code, internal code $code)");

    # Find the full error message
    my $message;
    $vars->{error} = $error;
    my $template = Bugzilla->template;
    $template->process("global/$type-error.html.tmpl", $vars, \$message)
      || die $template->error();

    my $error = {
      error         => 1,
      code          => $code,
      message       => $message,
      documentation => 'https://bmo.readthedocs.io/en/latest/api/',
    };

    $c->render(json => $error, status => $status_code);
  }
}

sub _make_logfunc {
  my ($type) = @_;
  my $logger = Log::Log4perl->get_logger("Bugzilla.Error.$type");
  return sub {
    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 3;
    if ($type eq 'User') {
      $logger->warn(@_);
    }
    else {
      $logger->error(@_);
    }
  };
}

1;
