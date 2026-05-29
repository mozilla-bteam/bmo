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
  use_ok('Bugzilla::Util');
}

my $safe_func     = \&Bugzilla::Attachment::is_safe_inline_content_type;
my $isolated_func = \&Bugzilla::Util::attachment_base_is_isolated;

# --- attachment_base_is_isolated ---

# Stub Bugzilla->localconfig to control attachment_base / urlbase values.
{
  no warnings qw(redefine once);
  my ($stub_attachbase, $stub_urlbase);
  local *Bugzilla::localconfig = sub {
    return bless {attachment_base => $stub_attachbase, urlbase => $stub_urlbase,},
      'FakeLocalconfig';
  };

  # FakeLocalconfig accessor
  *FakeLocalconfig::attachment_base = sub { $_[0]->{attachment_base} };
  *FakeLocalconfig::urlbase         = sub { $_[0]->{urlbase} };

  # Different host — isolated
  $stub_attachbase = 'https://attachments.example.com/';
  $stub_urlbase    = 'https://bugzilla.example.com/';
  ok($isolated_func->(),
    'different hosts: attachment_base_is_isolated returns true');

  # Same host, different path — not isolated
  $stub_attachbase = 'https://bugzilla.example.com/attachments/';
  $stub_urlbase    = 'https://bugzilla.example.com/';
  ok(!$isolated_func->(),
    'same host different path: attachment_base_is_isolated returns false');

  # Empty attachment_base
  $stub_attachbase = '';
  $stub_urlbase    = 'https://bugzilla.example.com/';
  ok(!$isolated_func->(),
    'empty attachment_base: attachment_base_is_isolated returns false');

  # attachment_base same as urlbase
  $stub_attachbase = 'https://bugzilla.example.com/';
  $stub_urlbase    = 'https://bugzilla.example.com/';
  ok(!$isolated_func->(),
    'attachment_base equals urlbase: attachment_base_is_isolated returns false');

  # Case-insensitive host comparison
  $stub_attachbase = 'https://ATTACHMENTS.EXAMPLE.COM/';
  $stub_urlbase    = 'https://attachments.example.com/';
  ok(!$isolated_func->(),
    'same host different case: attachment_base_is_isolated returns false');

  # %bugid% substitution should not break host parsing
  $stub_attachbase = 'https://bug%bugid%.attachments.example.com/';
  $stub_urlbase    = 'https://bugzilla.example.com/';
  ok($isolated_func->(),
    '%bugid% in attachment_base: attachment_base_is_isolated returns true');

  # --- is_safe_inline_content_type without isolation ---

  $stub_attachbase = '';
  $stub_urlbase    = 'https://bugzilla.example.com/';

  # Always-safe types (regardless of isolation)
  for my $type (qw(image/png image/jpeg text/plain text/csv application/pdf)) {
    ok($safe_func->($type), "$type always safe inline");
  }
  for my $type (qw(audio/mpeg video/mp4)) {
    ok($safe_func->($type), "$type (audio/video) always safe inline");
  }

  # text/html NOT safe without isolated attachment_base
  ok(!$safe_func->('text/html'), 'text/html not safe without isolated domain');
  ok(!$safe_func->('text/html; charset=utf-8'),
    'text/html with params not safe without isolated domain');

  # Other executable types always blocked
  for my $type (
    qw(image/svg+xml application/xhtml+xml text/xml application/javascript text/javascript)
    )
  {
    ok(!$safe_func->($type), "$type blocked regardless of isolation");
  }

  # --- is_safe_inline_content_type with isolation ---

  $stub_attachbase = 'https://attachments.example.com/';
  $stub_urlbase    = 'https://bugzilla.example.com/';

  ok($safe_func->('text/html'), 'text/html safe on isolated domain');
  ok(
    $safe_func->('text/html; charset=utf-8'),
    'text/html with params safe on isolated domain'
  );
  ok($safe_func->('TEXT/HTML'), 'text/html uppercase safe on isolated domain');

  # svg/xml still blocked even on isolated domain
  for my $type (
    qw(image/svg+xml application/xhtml+xml text/xml application/javascript))
  {
    ok(!$safe_func->($type), "$type still blocked on isolated domain");
  }
}

done_testing();
