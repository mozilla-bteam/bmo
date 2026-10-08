#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;

use Test2::V0;

use Bugzilla;
BEGIN { Bugzilla->extensions }

my $extract = \&Bugzilla::Extension::Needinfo::_extract_mentions;

is([$extract->(undef)], [], 'undef text');
is([$extract->('no mentions here')], [], 'no mentions');
is([$extract->('@alice can you look?')], ['alice'], 'leading mention');
is([$extract->('thanks @alice, @bob and @carol.')],
  ['alice', 'bob', 'carol'], 'multiple mentions with punctuation');
is([$extract->('@alice and @Alice again @alice')], ['alice'],
  'duplicates collapsed case-insensitively');
is([$extract->('(@dk.l_x-y)')], ['dk.l_x-y'], 'nick symbols, parens');
is([$extract->('mail foo@example.com or a/@b or x.@y')], [],
  'emails and embedded @ ignored');
is([$extract->("> \@quoted said\n\@alice")], ['alice'], 'quoted lines ignored');
is([$extract->('run `@decorator` @alice')], ['alice'], 'inline code ignored');
is(
  [$extract->("```perl\n\@inside\n```\n\@after")],
  ['after'], 'fenced code block ignored'
);
is([$extract->("~~~\n\@unclosed\n\@more")], [], 'unclosed fence runs to end');

done_testing;
