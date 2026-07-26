#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
  $ENV{LOG4PERL_CONFIG_FILE} = 'log4perl-t.conf';
  $ENV{MOJO_MAX_MESSAGE_SIZE} = 512;
}

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (maxattachmentsize => 10_240);

use Test2::V0;
use Test::Mojo;

my $boundary = 'bugzilla-request-limit';
my $body = join(
  "\r\n",
  "--$boundary",
  'Content-Disposition: form-data; name="bug_type"',
  '',
  'defect',
  "--$boundary",
  'Content-Disposition: form-data; name="data"; filename="large.txt"',
  'Content-Type: text/plain',
  '',
  'x' x 512,
  "--$boundary--",
  ''
);

my $t = Test::Mojo->new('Bugzilla::App');
$t->post_ok(
  '/post_bug.cgi' => {
    'Content-Length' => length($body),
    'Content-Type'   => "multipart/form-data; boundary=$boundary",
  } => $body
)->status_is(413)
  ->header_is('Content-Type' => 'text/plain; charset=UTF-8')
  ->content_is("The request is too large. Attachments are limited to 10 MB.\n")
  ->content_unlike(qr/bug_type/i);

done_testing;
