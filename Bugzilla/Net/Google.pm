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
use Mojo::JSON qw(decode_json);
use Mojo::JWT;
use Moo;
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

# Add new data to net storage
sub add_key {
  my ($self, $key, $value) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $path_format
    = 'upload/'
    . $PATH_BASE
    . '/%s/o?uploadType=media&name='
    . uri_escape_utf8($key);

  my $request
    = $self->_make_request('POST', $self->_uri($path_format, $self->bucket),
    $value);
  my $response = $self->_do_http($request);

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return undef;
}

# Check if a key exists in net storage
sub head_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $path_format = $PATH_BASE . '/%s/o/%s';
  my $request
    = $self->_make_request('GET', $self->_uri($path_format, $self->bucket, $key));
  my $response = $self->_do_http($request);

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return undef;
}

# Get data from net storage
sub get_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $path_format = $PATH_BASE . '/%s/o/%s?alt=media';
  my $request
    = $self->_make_request('GET', $self->_uri($path_format, $self->bucket, $key));
  my $response = $self->_do_http($request);

  if ($response->code =~ /^2\d\d$/) {
    return $response->decoded_content || '';
  }

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return undef;
}

sub delete_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $path_format = $PATH_BASE . '/%s/o/%s';
  my $request     = $self->_make_request('DELETE',
    $self->_uri($path_format, $self->bucket, $key));
  my $response = $self->_do_http($request);

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return 0;
}

###################
# Private methods #
###################

sub _uri {
  my ($self, $format, @args) = @_;
  my @escaped_args = map { uri_escape_utf8($_) } @args;
  return sprintf $format, @escaped_args;
}

sub _add_auth_header {
  my ($self, $headers) = @_;

  # Do not add Authorization header if running CI tests
  return undef if !$self->service_account;

  if (!$self->access_token || time > $self->access_token_expiry) {
    $self->_get_access_token;
  }

  $headers->header(Authorization => 'Bearer ' . $self->access_token);
}

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

# returns 1 if errors were found
sub _remember_errors {
  my ($self, $response) = @_;

  # my $src = $response->content;
  #

  # unless (ref $src || $src =~ m/^[[:space:]]*</) {    # if not xml
  #   (my $code = $src) =~ s/^[[:space:]]*\([0-9]*\).*$/$1/;
  #   $self->error_code($code);
  #   $self->error_string($src);
  #   return 1;
  # }
  #
  # my $r = ref $src ? $src : $self->_xpc_of_content($src);
  #
  # if ($r->{Error}) {
  #   $self->error_code($r->{Error}{Code});
  #   $self->error_string($r->{Error}{Message});
  #   return 1;
  # }

  return 0;
}

1;

