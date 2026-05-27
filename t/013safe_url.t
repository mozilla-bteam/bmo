# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##################
#Bugzilla Test 13#
###safe_url#######

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);

use Bugzilla::Constants;
use Bugzilla::Util qw(is_safe_url);
use Test::More;

# view-source must not be in SAFE_PROTOCOLS (regression guard)
my @safe_protocols = (SAFE_PROTOCOLS);
ok(!grep { $_ eq 'view-source' } @safe_protocols,
  'view-source is NOT in SAFE_PROTOCOLS');

my @safe_cases = (
  ['http://example.com/',           'plain http URL'],
  ['https://example.com/path?x=1',  'https URL with query string'],
  ['ftp://ftp.example.com/file',    'ftp URL'],
  ['local/relative/path',           'local relative path (no colon)'],
  ['local/relative/path/',          'local relative path ending with slash'],
);

my @unsafe_cases = (
  ['view-source:javascript:alert(1)',   'view-source:javascript: bypass (CVE case)'],
  ['view-source:http://example.com/',   'view-source:http:// no longer safe'],
  ['javascript:alert(1)',               'javascript: scheme'],
  ['JAVASCRIPT:alert(1)',               'javascript: scheme uppercase'],
  ['data:text/html,<script>x</script>', 'data: scheme'],
  ['vbscript:msgbox(1)',                'vbscript: scheme'],
  ['mailto:user@example.com',           'mailto: (not in SAFE_PROTOCOLS)'],
  ['',                                  'empty string'],
  [undef,                               'undef'],
);

for my $tc (@safe_cases) {
  my ($url, $desc) = @$tc;
  ok(is_safe_url($url), "SAFE: $desc");
}

for my $tc (@unsafe_cases) {
  my ($url, $desc) = @$tc;
  ok(!is_safe_url($url), "UNSAFE: $desc");
}

done_testing;
