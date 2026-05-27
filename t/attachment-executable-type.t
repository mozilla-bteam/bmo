# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);
use Test::More;

BEGIN {
  use_ok('Bugzilla::Attachment');
}

my $func = \&Bugzilla::Attachment::is_executable_content_type;

# Safe types — must be served inline
my @safe = (
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/avif',
  'image/bmp',
  'image/x-icon',
  'application/pdf',
  'text/plain',
  'text/csv',
  'audio/mpeg',
  'audio/ogg',
  'audio/wav',
  'video/mp4',
  'video/webm',
  'video/ogg',
);

# Executable types — must be forced to attachment
my @executable = (
  'image/svg+xml',
  'text/html',
  'application/xhtml+xml',
  'application/xml',
  'text/xml',
  'application/mathml+xml',
  'application/javascript',
  'text/javascript',
  'application/x-javascript',
  'application/octet-stream',
  'application/zip',
  'text/css',
);

for my $type (@safe) {
  ok(!$func->($type),                    "$type is safe");
  ok(!$func->(uc($type)),                "$type (uppercase) is safe");
  ok(!$func->("$type; charset=utf-8"),   "$type with params is safe");
}

for my $type (@executable) {
  ok($func->($type),                  "$type is executable");
  ok($func->(uc($type)),              "$type (uppercase) is executable");
  ok($func->("$type; charset=utf-8"), "$type with params is executable");
}

ok($func->(undef), 'undef is executable');
ok($func->(''),    'empty string is executable');

done_testing();
