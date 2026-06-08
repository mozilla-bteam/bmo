#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Regression test: object_before_create must block near-match mimetypes that
# would be normalized to PHAB_CONTENT_TYPE by the attachment validator.
# Without clean_text(), "text/x-phabricator-request " (trailing space) or
# "text/x-phabricator-request\x00" (null byte) bypass the eq check but are
# stored as the privileged type by _check_content_type -> clean_text.

use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );
use Bugzilla;

BEGIN { Bugzilla->extensions }

use Test::More;
use Test2::Tools::Mock;

use Bugzilla::Extension::PhabBugz::Constants qw(PHAB_CONTENT_TYPE);

# request_cache is a use constant — set key directly on the hashref.
Bugzilla->request_cache->{allow_phab_revision_attachment} = 0;

my $BugzillaUser = mock 'Bugzilla::User' => (
  add_constructor => [fake_new => 'hash'],
  override        => [login   => sub { 'attacker@example.com' }],
);

my $Bugzilla = mock 'Bugzilla' => (
  override => [
    'user'  => sub { Bugzilla::User->fake_new(id => 1) },
    'audit' => sub { },
  ],
);

# Extensions are called as class methods by Hook::process.
sub run_hook {
  my ($mimetype) = @_;
  my $params = {mimetype => $mimetype};
  Bugzilla::Extension::PhabBugz->object_before_create({
    class  => 'Bugzilla::Attachment',
    params => $params,
  });
  return $params->{mimetype};
}

# Exact match — must be blocked.
is(run_hook(PHAB_CONTENT_TYPE), undef, 'exact PHAB_CONTENT_TYPE blocked');

# Trailing-space variant — storage trims this; hook must block it too.
is(run_hook(PHAB_CONTENT_TYPE . ' '), undef, 'trailing-space variant blocked');

# Leading-space variant.
is(run_hook(' ' . PHAB_CONTENT_TYPE), undef, 'leading-space variant blocked');

# Null-byte variant — clean_text replaces \x00 with space then trims;
# result equals PHAB_CONTENT_TYPE so hook must catch it.
is(run_hook(PHAB_CONTENT_TYPE . "\x00"), undef, 'null-byte variant blocked');

# Unrelated mimetype — must pass through unchanged.
is(run_hook('text/plain'), 'text/plain', 'benign mimetype allowed');

done_testing;
