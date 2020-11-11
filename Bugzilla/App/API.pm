# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::API;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Logging;
use Bugzilla::Util qw(datetime_from);

use MIME::Base64 qw(encode_base64);
use Module::Runtime qw(require_module);
use Mojo::JSON qw(false true);
use Mojo::Loader qw( find_modules );
use Try::Tiny;

use constant SUPPORTED_VERSIONS => qw(V1);

sub setup_routes {
  my ($class, $r, $app) = @_;

  # Add Bugzilla::API to namespaces for searching for controllers
  my $namespaces = $r->namespaces;
  push @$namespaces, 'Bugzilla::API';
  $r->namespaces($namespaces);

  foreach my $version (SUPPORTED_VERSIONS) {
    foreach my $module (find_modules("Bugzilla::API::$version")) {
      try {
        require_module($module);
        my $controller = $module->new;
        if ($controller->can('setup_routes')) {
          $controller->setup_routes($r);
        }
      }
      catch {
        WARN("$module could not be loaded");
      };
    }
  }

  # Add handler for setting JSON data type properly
  $app->helper('type' => sub { _type(@_); });
}

sub _type {
  my ($self, $type, $value) = @_;

  # This is the only type that does something special with undef.
  if ($type eq 'boolean') {
    return $value ? true : false;
  }

  return undef if !defined $value;

  my $retval = $value;

  if ($type eq 'int') {
    $retval = int($value);
  }
  if ($type eq 'double') {
    $retval = 0.0 + $value;
  }
  elsif ($type eq 'string') {

    # Forces string context, so that JSON will make it a string.
    $retval = "$value";
  }
  elsif ($type eq 'dateTime') {

    # ISO-8601 "YYYYMMDDTHH:MM:SS" with a literal T
    $retval = _datetime_format_outbound($value);
  }
  elsif ($type eq 'base64') {
    utf8::encode($value) if utf8::is_utf8($value);
    $retval = encode_base64($value, '');
  }
  elsif ($type eq 'email' && Bugzilla->params->{'webservice_email_filter'}) {
    $retval = email_filter($value);
  }

  return $retval;
}

sub _datetime_format_outbound {
  my ($date) = @_;

  return undef if (!defined $date or $date eq '');

  my $time = $date;
  if (blessed($date)) {

    # We expect this to mean we were sent a datetime object
    $time->set_time_zone('UTC');
  }
  else {
    # We always send our time in UTC, for consistency.
    # passed in value is likely a string, create a datetime object
    $time = datetime_from($date, 'UTC');
  }

  return $time->iso8601();
}
1;
