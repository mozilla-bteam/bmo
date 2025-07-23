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
use autodie;
use lib qw(. lib local/lib/perl5);
use IO::Handle;
use Test::More;

my $dockerfile = 'Dockerfile.bmo-slim';

my $base;
open my $dockerfile_fh, '<', $dockerfile;
while (my $line = readline $dockerfile_fh) {
  chomp $line;
  if ($line =~ /^FROM\s+(\S+)/ms) {
    $base = $1;
    last;
  }
}
close $dockerfile_fh;

my ($image, $version) = split(/:/ms, $base, 2);
is($image, 'perl', 'base image is Perl');
like($version, qr/\d{1}\.\d{2}\.\d{1}-slim/ms, "version is x.xx.x-slim");

done_testing;
