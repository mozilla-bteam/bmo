#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Test for REST call to Bug.add_attachment()        #
# POST /rest/bug/<id>/attachment                      #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use MIME::Base64 qw(encode_base64 decode_base64);
use QA::Util qw(get_config random_string);
use QA::REST::Util qw(api_headers create_test_bugs);

use Test::Mojo;
use Test::More;

my $config = get_config();
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

use constant INVALID_BUG_ID    => -1;
use constant INVALID_BUG_ALIAS => random_string(20);

sub attach {
  my ($id, $override) = @_;
  my %fields = (
    ids          => [$id],
    data         => 'data-' . random_string(100),
    file_name    => 'file_name-' . random_string(60),
    summary      => 'summary-' . random_string(100),
    content_type => 'text/plain',
    comment      => 'comment-' . random_string(100),
  );

  foreach my $key (keys %{$override || {}}) {
    my $value = $override->{$key};
    if (defined $value) {
      $fields{$key} = $value;
    }
    else {
      delete $fields{$key};
    }
  }
  return \%fields;
}

my ($public_bug, $private_bug)
  = create_test_bugs($t, $config, $url, second_private => 1);
my $public_id  = $public_bug->{id};
my $private_id = $private_bug->{id};

my @tests = (

  # Permissions
  {args => attach($public_id), error => 'You must log in', test => 'Logged-out user cannot add an attachment to a public bug'},
  {args => attach($private_id), error => "You must log in", test => 'Logged-out user cannot add an attachment to a private bug'},
  {user => 'editbugs', args => attach($private_id), error => "not authorized to access", test => "Editbugs user can't add an attachment to a private bug"},

  # Test ID parameter
  {user => 'unprivileged', args => attach(INVALID_BUG_ID), error => "It does not seem like bug number", test => 'Passing invalid bug id returns error "Invalid Bug ID"'},
  {user => 'unprivileged', args => attach(INVALID_BUG_ALIAS), error => "nor an alias to a bug", test => 'Passing invalid bug alias returns error "Invalid Bug Alias"'},

  # Test data parameter
  {user => 'unprivileged', args => attach($public_id, {data => undef}), error => 'a data argument', test => 'Failing to pass the "data" parameter fails'},
  {user => 'unprivileged', args => attach($public_id, {data => ''}), error => "The file you are trying to attach is empty", test => 'Passing empty data fails'},
  {user => 'unprivileged', args => attach($public_id, {data => random_string(300_000)}), error => "Attachments cannot be more than", test => "Passing an attachment that's too large fails"},

  # Test the private parameter
  {user => 'unprivileged', args => attach($public_id, {is_private => 1}), error => 'attachments as private', test => 'Unprivileged user cannot add a private attachment'},

  # Content-type
  {user => 'unprivileged', args => attach($public_id, {content_type => 'foo/bar'}), error => "Valid types must be of the form", test => "Well-formed but invalid content type fails"},
  {user => 'unprivileged', args => attach($public_id, {content_type => undef}), error => 'Valid types must be of the form', test => "Failing to pass content_type fails"},
  {user => 'unprivileged', args => attach($public_id, {content_type => ''}), error => 'Valid types must be of the form', test => "Empty content type fails"},

  # Summary
  {user => 'unprivileged', args => attach($public_id, {summary => undef}), error => 'You must enter a description for the attachment', test => "Failing to pass summary fails"},
  {user => 'unprivileged', args => attach($public_id, {summary => ''}), error => 'You must enter a description for the attachment', test => "Empty summary fails"},

  # Filename
  {user => 'unprivileged', args => attach($public_id, {file_name => undef}), error => 'You did not specify a file to attach', test => "Failing to pass file_name fails"},
  {user => 'unprivileged', args => attach($public_id, {file_name => ''}), error => 'You did not specify a file to attach', test => "Empty file_name fails"},

  # Success tests
  {user => 'unprivileged', args => attach($public_id), test => 'Unprivileged user can add an attachment to a public bug'},
  {user => 'unprivileged', args => attach($public_id, {is_patch => 1, content_type => undef}), test => 'Attaching a patch with no content type works'},
  {user => 'unprivileged', args => attach($public_id, {is_patch => 1, content_type => 'application/octet-stream'}), test => 'Attaching a patch with a bad content_type works'},
  {user => 'QA_Selenium_TEST', args => attach($private_id), test => 'Privileged user can add an attachment to a private bug'},
  {user => 'QA_Selenium_TEST', args => attach($public_id, {is_private => 1}), test => 'Insidergroup user can add a private attachment'},
);

foreach my $test (@tests) {
  my %args = %{$test->{args}};
  my $ids  = delete $args{ids};
  my $id   = $ids ? $ids->[0] : undef;

  # The RPC-only missing/empty bug id cases have no REST URL equivalent.
  next if !defined $id || $id eq '';

  my $raw_data = $args{data};
  $args{data} = encode_base64($args{data}, '') if defined $args{data};

  my $api_key = $test->{user} ? $config->{"$test->{user}_user_api_key"} : undef;
  my $headers = api_headers($api_key);
  my $path    = $url . "rest/bug/$id/attachment";

  if (my $error = $test->{error}) {
    $t->post_ok($path => $headers => json => \%args)->status_isnt(200);
    like($t->tx->res->json->{message}, qr/\Q$error\E/, "$test->{test}: $error");
    next;
  }

  $t->post_ok($path => $headers => json => \%args)->status_is(201);
  my ($attach_id) = keys %{$t->tx->res->json->{attachments}};

  $t->get_ok($url . "rest/bug/attachment/$attach_id" => $headers)->status_is(200);
  my $attachment = $t->tx->res->json->{attachments}->{$attach_id};

  if ($test->{args}{is_private}) {
    ok($attachment->{is_private}, "Attachment $attach_id is private");
  }
  else {
    ok(!$attachment->{is_private}, "Attachment $attach_id is NOT private");
  }

  if ($test->{args}{is_patch}) {
    is($attachment->{content_type}, 'text/plain',
      "Patch $attach_id content type is text/plain");
  }
  else {
    is($attachment->{content_type}, $test->{args}{content_type},
      "Attachment $attach_id content type is correct");
  }

  is(decode_base64($attachment->{data}), $raw_data,
    "Attachment $attach_id data is correct");
}

done_testing();
