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
use lib qw( . lib local/lib/perl5 );

use Safe;
use Test::More;

use Bugzilla::Constants;

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;

# Write out the data/params file for migration
my $datadir = bz_locations()->{'datadir'};
open my $data_fh, '>:encoding(UTF-8)', "$datadir/params"
  or die "Could not open data file for writing: $!";
print $data_fh <DATA>;
close $data_fh;
close DATA;

ok(-f "$datadir/params", 'Original parameters file exists');

my $params = Bugzilla::Config->new;
$params->migrate_params();

# Read file back as a Perl data structure for comparison
ok(-f "$datadir/params.old", 'Backup parameters file exists');
my $s = Safe->new;
$s->rdo("$datadir/params.old");
my %file_params = %{$s->varglob('param')};
ok(scalar keys %file_params, 'Parameters file read back correctly');

# Make copy of the newly updated database parameters
my %db_params = %{Bugzilla->params};

foreach my $param (keys %file_params) {
  ok($file_params{$param} eq $db_params{$param}, "$param matches");
}

done_testing;

1;

__DATA__
%param = (
           'attachment_storage' => 's3',
           'bitly_token' => 'BITLY_TOKEN',
           'github_client_id' => 'GITHUB_CLIENT_ID',
           'honeypot_api_key' => 'HONEYPOT_API_KEY',
           'iprepd_client_secret' => 'IPREPD_CLIENT_SECRET',
           'phabricator_api_key' => 'PHABRICATOR_API_KEY',
         );
