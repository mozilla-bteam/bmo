#!/usr/bin/env perl
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

use Bugzilla::Test::Files;
use Test::More;

my @testitems = (
  @Bugzilla::Test::Files::testitems, @Bugzilla::Test::Files::test_files,
  @Bugzilla::Test::Files::scripts
);

my $ok = eval { require Test::Perl::Critic::Progressive };
plan skip_all => 'T::P::C::Progressive required for this test' unless $ok;

Test::Perl::Critic::Progressive::progressive_critic_ok(@testitems);
