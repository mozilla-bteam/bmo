# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Net::S3;

use 5.10.1;
use strict;
use warnings;

use Digest::HMAC_SHA1;
use HTTP::Date;
use MIME::Base64 qw(encode_base64);
use Moo;
use Types::Standard qw(Str);
use URI::Escape     qw(uri_escape_utf8);
use XML::Simple;

use Bugzilla::Error;
use Bugzilla::Util qw(trim);

extends 'Bugzilla::Net::Storage';

has client_id  => (is => 'ro', required => 1, isa => Str);
has secret_key => (is => 'ro', required => 1, isa => Str);

##################
# Public methods #
##################

# Return type of net storage
sub data_type { return 's3'; }

# Add new data to net storage
sub add_key {
  my ($self, $key, $value) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $headers = {};
  $headers->{'Content-Length'} = length $value;

  my $request  = $self->_make_request('PUT', $self->_uri($key), $value, $headers);
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

  my $request  = $self->_make_request('HEAD', $self->_uri($key));
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

  my $request  = $self->_make_request('GET', $self->_uri($key));
  my $response = $self->_do_http($request);

  if ($response->code =~ /^2\d\d$/) {
    return $response->decoded_content;
  }

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return undef;
}

sub delete_key {
  my ($self, $key) = @_;

  ThrowCodeError('net_storage_invalid_key') unless $key && length $key;

  my $request  = $self->_make_request('DELETE', $self->_uri($key));
  my $response = $self->_do_http($request);

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response);

  return 0;
}

###################
# Private methods #
###################

# EU buckets must be accessed via their DNS name. This routine figures out if
# a given bucket name can be safely used as a DNS name.
sub _is_dns_bucket {
  my ($self, $bucketname) = @_;

  if (length $bucketname > 63) {
    return 0;
  }

  if (length $bucketname < 3) {
    return undef;
  }

  return 0 unless $bucketname =~ m{^[a-z0-9][a-z0-9.-]+$};

  my @components = split /[.]/, $bucketname;
  for my $c (@components) {
    return 0 if $c =~ m{^-};
    return 0 if $c =~ m{-$};
    return 0 if $c eq '';
  }

  return 1;
}

# generate a canonical string for the given parameters.
sub _canonical_string {
  my ($self, $method, $path, $headers) = @_;

  my %interesting_headers = ();
  foreach my $key ($headers->header_field_names) {
    my $lk = lc $key;
    if ($lk eq 'content-md5' or $lk eq 'content-type' or $lk eq 'date') {
      $interesting_headers{$lk} = trim($headers->header($key));
    }
  }

  # these keys get empty strings if they don't exist
  $interesting_headers{'content-type'} ||= '';
  $interesting_headers{'content-md5'}  ||= '';

  my $buf = "$method\n";
  foreach my $key (sort keys %interesting_headers) {
    $buf .= "$interesting_headers{$key}\n";
  }

  # don't include anything after the first ? in the resource...
  $path =~ /^([^?]*)/;
  $buf .= "/$1";

  return $buf;
}

sub _add_auth_header {
  my ($self, $headers, $method, $path) = @_;
  my $aws_access_key_id     = $self->client_id;
  my $aws_secret_access_key = $self->secret_key;

  if (!$headers->header('Date')) {
    $headers->header('Date' => time2str(time));
  }

  my $canonical_string = $self->_canonical_string($method, $path, $headers);
  my $encoded_canonical
    = $self->_encode($aws_secret_access_key, $canonical_string);

  $headers->header(Authorization => "AWS $aws_access_key_id:$encoded_canonical");
}

# finds the hmac-sha1 hash of the canonical string and the aws secret access key
# and then base64 encodes the result.
sub _encode {
  my ($self, $aws_secret_access_key, $str) = @_;
  my $hmac = Digest::HMAC_SHA1->new($aws_secret_access_key);
  $hmac->add($str);
  return encode_base64($hmac->digest, '');
}

sub _uri {
  my ($self, $key) = @_;
  return ($key)
    ? $self->bucket . '/' . uri_escape_utf8($key)
    : $self->bucket . '/';
}

sub _xpc_of_content {
  my ($self, $content) = @_;
  return XMLin(
    $content,
    'KeepRoot'      => 1,
    'SuppressEmpty' => '',
    'ForceArray'    => ['Contents']
  );
}

# returns 1 if errors were found
sub _remember_errors {
  my ($self, $response) = @_;
  my $src = $response->content;

  unless (ref $src || $src =~ m/^[[:space:]]*</) {    # if not xml
    (my $code = $src) =~ s/^[[:space:]]*\([0-9]*\).*$/$1/;
    $self->error_code($code);
    $self->error_string($src);
    return 1;
  }

  my $r = ref $src ? $src : $self->_xpc_of_content($src);

  if ($r->{Error}) {
    $self->error_code($r->{Error}{Code});
    $self->error_string($r->{Error}{Message});
    return 1;
  }

  return 0;
}

1;
