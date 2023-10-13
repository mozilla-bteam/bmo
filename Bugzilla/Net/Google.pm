# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Net::Google;

use 5.10.1;
use strict;
use warnings;

use HTTP::Headers;
use HTTP::Request;
use List::Util qw(none);
use Mojo::JSON qw(decode_json);
use Mojo::JWT;
use Moo;
use Try::Tiny;
use Types::Standard qw(Int Str);
use URI::Escape     qw(uri_escape_utf8);

use Bugzilla::Error;

extends 'Bugzilla::Net::Storage';

has access_token        => (is => 'rw', isa => Str,);
has access_token_expiry => (is => 'rw', isa => Int,);
has service_account     => (is => 'ro', isa => Str,);

my $PATH_BASE = 'storage/v1/b';

##################
# Public methods #
##################

# Return type of net storage
sub data_type { return 'google'; }

###################
# Private methods #
###################

# Based on the type of action being performed, select the proper
# method and the path needed for the Google API.
sub _get_method_path {
  my ($self, $action, $key) = @_;
  my ($method, $format);
  my @args = ($self->bucket);

  if (none { $action eq $_ } qw(add head get delete)) {
    ThrowCodeError('net_storage_invalid_action', {action => $action});
  }

  if ($action eq 'add') {
    $format
      = 'upload/'
      . $PATH_BASE
      . '/%s/o?uploadType=media&name='
      . uri_escape_utf8($key);
    $method = 'POST';
  }
  elsif ($action eq 'head') {
    $format = $PATH_BASE . '/%s/o/%s';
    $method = 'GET';
    push @args, $key;
  }
  elsif ($action eq 'get') {
    $format = $PATH_BASE . '/%s/o/%s?alt=media';
    $method = 'GET';
    push @args, $key;
  }
  elsif ($action eq 'delete') {
    $format = $PATH_BASE . '/%s/o/%s';
    $method = 'DELETE';
    push @args, $key;
  }

  my @escaped_args = map { uri_escape_utf8($_) } @args;
  my $path         = sprintf $format, @escaped_args;

  return ($method, $path);
}

# Add the header needed for Google API authentication.
# Using an access token, we will authenticate using the
# OAuth2 workflow.
sub _add_auth_header {
  my ($self, $headers) = @_;

  # Do not add Authorization header if running CI tests
  return undef if !$self->service_account;

  if (!$self->access_token || time > $self->access_token_expiry) {
    $self->_get_access_token;
  }

  $headers->header(Authorization => 'Bearer ' . $self->access_token);
}

# Google Kubernetes allows for the user of Workload Identity. This allows
# us to link two serice accounts together and give special access for applications
# running under Kubernetes. We use the special access to get an OAuth2 access_token
# that can then be used for accessing the the Google API such as Cloud Storage.
sub _get_access_token {
  my ($self) = @_;
  my $url
    = sprintf
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/%s/token',
    $self->service_account;

  my $http_headers = HTTP::Headers->new;
  $http_headers->header('Metadata-Flavor' => 'Google');

  my $request = HTTP::Request->new('GET', $url, $http_headers);

  my $res = $self->ua->request($request);

  if (!$res->is_success) {
    ThrowCodeError('google_access_token_failure', {error => $res->content});
  }

  my $result = decode_json($res->decoded_content);

  $self->access_token($result->{access_token});
  $self->access_token_expiry(time + $result->{expires_in});
}

# Example Error:
# 401 Unauthorized
#
# {
# "error": {
#  "errors": [
#   {
#    "domain": "global",
#    "reason": "required",
#    "message": "Login Required",
#    "locationType": "header",
#    "location": "Authorization"
#   }
#  ],
#  "code": 401,
#  "message": "Login Required"
#  }
# }

# When an error occurs, Google API adds additional information
# in the response body in the form of JSON that we can use.
sub _remember_errors {
  my ($self, $response) = @_;

  try {
    my $content = $response->decoded_content;
    my $r       = ref $content ? $content : decode_json($content);
    if ($r->{error}) {
      $self->error_code($r->{error}{code});
      $self->error_string($r->{error}{message});
    }
  }
  catch {
    $self->error_code($response->code);
    $self->error_string($response->message);
  };
}

1;

