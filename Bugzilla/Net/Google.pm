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

use Bugzilla;
use Bugzilla::Error;

extends 'Bugzilla::Net::Storage';

has access_token        => (is => 'rw', isa => Str,);
has access_token_expiry => (is => 'rw', isa => Int,);
has service_account     => (is => 'ro', isa => Str,);
has min_datasize        => (is => 'lazy');

my $PATH_BASE = 'storage/v1/b';

##################
# Public methods #
##################

# Return type of net storage
sub data_type { return 'google'; }

###################
# Private methods #
###################

# Do not store data below a specific size on the network
sub _build_min_datasize {
  my ($self) = @_;
  return Bugzilla->params->{attachment_google_minsize};
}

# Based on the type of action being performed, select the proper
# method and the path needed for the Google API.
sub _get_method_path {
  my ($self, $action, $key) = @_;
  my ($method, $path);

  if (none { $action eq $_ } qw(add head get delete)) {
    ThrowCodeError('net_storage_invalid_action', {action => $action});
  }

  my $escaped_bucket = uri_escape_utf8($self->bucket);
  my $escaped_key    = uri_escape_utf8($key);

  if ($action eq 'add') {
    $path
      = "upload/${PATH_BASE}/${escaped_bucket}/o?uploadType=media&name=${escaped_key}";
    $method = 'POST';
  }
  elsif ($action eq 'head') {
    $path   = "${PATH_BASE}/${escaped_bucket}/o/${escaped_key}";
    $method = 'GET';
  }
  elsif ($action eq 'get') {
    $path   = "${PATH_BASE}/${escaped_bucket}/o/${escaped_key}?alt=media";
    $method = 'GET';
  }
  elsif ($action eq 'delete') {
    $path   = "${PATH_BASE}/${escaped_bucket}/o/${escaped_key}";
    $method = 'DELETE';
  }

  return ($method, $path);
}

# Add the header needed for Google API authentication.
# Using an access token, we will authenticate using the
# OAuth2 workflow.
sub _add_auth_header {
  my ($self, $headers) = @_;

  # Do not add Authorization header if running CI tests
  return undef if $self->service_account eq 'test';

  if (!$self->access_token || time > $self->access_token_expiry) {
    $self->_get_access_token;
  }

  $headers->header(Authorization => 'Bearer ' . $self->access_token);
}

# Google Kubernetes allows for the use of Workload Identity. This allows
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
    ThrowCodeError('google_access_token_failure', {reason => $res->content});
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
    my $content         = $response->decoded_content;
    my $decoded_content = ref $content ? $content : decode_json($content);
    if ($decoded_content->{error}) {
      $self->error_code($decoded_content->{error}{code});
      $self->error_string($decoded_content->{error}{message});
    }
  }
  catch {
    $self->error_code($response->code);
    $self->error_string($response->message);
  };
}

# If we are running under a test environment, then override
# the protocol and host to match the docker containers mocking
# the api.
sub _check_for_test_environment {
  my ($self, $protocol, $host) = @_;
  if ($self->host eq 'gcs') {
    return ('http', 'gcs:4443');
  }
  return ($protocol, $host);
}

1;

