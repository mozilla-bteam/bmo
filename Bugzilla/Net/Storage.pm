# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Net::Storage;

use 5.10.1;
use strict;
use warnings;

use HTTP::Headers;
use HTTP::Request;
use LWP::UserAgent;
use Moo;
use Types::Standard qw(Bool Int Object Str);

has bucket       => (is => 'ro',   required => 1, isa => Str);
has host         => (is => 'ro',   required => 1, isa => Str);
has ua           => (is => 'lazy', isa      => Object);
has retry        => (is => 'ro',   isa      => Bool, default => 1);
has secure       => (is => 'ro',   isa      => Bool, default => 1);
has timeout      => (is => 'ro',   isa      => Int,  default => 30);
has error_code   => (is => 'rw',   isa      => Int | Str);
has error_string => (is => 'rw',   isa      => Str);
has port         => (is => 'ro',   isa      => Int);

##################
# Public Methods #
##################

# Add new data to net storage
sub add_key {
  my ($self, $key, $value) = @_;

  ThrowCodeError('net_storage_invalid_key')   unless $key   && length $key;
  ThrowCodeError('net_storage_invalid_value') unless $value && length $value;

  my ($method, $path) = $self->_get_method_path('add', $key);

  return $self->_send_request($method, $path, $value);
}

# Check if a key exists in net storage
sub head_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my ($method, $path) = $self->_get_method_path('head', $key);

  return $self->_send_request($method, $path);
}

# Get data from net storage
sub get_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my ($method, $path) = $self->_get_method_path('get', $key);

  return $self->_send_request($method, $path);
}

# Delete data from net storage
sub delete_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my ($method, $path) = $self->_get_method_path('delete', $key);

  return $self->_send_request($method, $path);
}

###################
# Private Methods #
###################

sub _build_ua {
  my ($self) = @_;

  my $ua;
  if ($self->retry) {
    require LWP::UserAgent::Determined;
    $ua = LWP::UserAgent::Determined->new(
      agent                 => 'Bugzilla',
      keep_alive            => 10,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
    $ua->timing('1,2,4,8,16,32');
  }
  else {
    $ua = LWP::UserAgent->new(
      agent                 => 'Bugzilla',
      keep_alive            => 10,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
  }
  $ua->timeout($self->timeout);
  if (my $proxy = Bugzilla->params->{proxy_url}) {
    $ua->proxy(['https', 'http'], $proxy);
  }

  return $ua;
}

sub _remember_errors {
  my ($self, $response) = @_;
  $self->error_code($response->code);
  $self->error_string($response->status_line);
}

# make the HTTP::Request object
sub _make_request {
  my ($self, $method, $path, $data, $headers) = @_;
  $headers ||= {};
  $data //= '';

  my $http_headers = HTTP::Headers->new;
  foreach my $key (keys %{$headers}) {
    $http_headers->header($key => $headers->{$key});
  }

  $self->_add_auth_header($http_headers, $method, $path);

  my $protocol = $self->secure ? 'https'                         : 'http';
  my $host     = $self->port   ? $self->host . ':' . $self->port : $self->host;

  # Override protocol and host if we are running in a test environment
  ($protocol, $host) = $self->_check_for_test_environment($protocol, $host);

  my $url = "$protocol://$host/$path";

  if ( $self->host ne 's3'
    && $self->can('_is_dns_bucket')
    && $path =~ m{^([^/?]+)(.*)})
  {
    my $bucket    = $1;
    my $full_path = $2;
    if ($self->_is_dns_bucket($bucket)) {
      $url = "$protocol://$bucket." . $host . $full_path;
    }
  }

  my $request = HTTP::Request->new($method, $url, $http_headers);

  # works only with bytes, not with UTF-8 strings.
  if (utf8::is_utf8($data)) {
    utf8::encode($data);
  }

  $request->content($data);

  return $request;
}

# centralize all HTTP work, for debugging
sub _do_http {
  my ($self, $request) = @_;

  # convenient time to reset any error conditions
  $self->error_code(0);
  $self->error_string('');

  return $self->ua->request($request);
}

# Send the request and return data if requested
sub _send_request {
  my ($self, $method, $path, $value) = @_;

  my $request  = $self->_make_request($method, $path, $value);
  my $response = $self->_do_http($request);

  if ($response->code =~ /^2\d\d$/) {
    if ($method eq 'GET') {
      return $response->decoded_content;
    }
    else {
      return 1;
    }
  }

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return 0;
}

1;

