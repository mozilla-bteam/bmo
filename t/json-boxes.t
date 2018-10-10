#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

use Scalar::Util qw(weaken);
use Test2::V0;

use ok 'Bugzilla::WebService::JSON';

my $json = Bugzilla::WebService::JSON->new;
my $ref = {foo => 1};
ok($json->decode($json->encode($ref)) == $ref);

$json->allow_nonref;

my $ref2 = ['foo'];

ok($json->decode($json->encode($ref2)) == $ref2);

my $box = $json->retain($ref2);

is($box->json_value, q{["foo"]});

weaken($box);
ok(defined($box), "box is defined before cache clear");
$json->clear_cache;
ok(!defined($box), "box is not defined after cache clear");

my $arrayref = $json->decode('[42]');
ok( $json->decode( $json->encode($arrayref) ) == $arrayref );

done_testing;
