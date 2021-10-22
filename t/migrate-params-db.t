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

# Write out the data/params file for migration
my $datadir = bz_locations()->{'datadir'};
open my $data_fh, '>:encoding(UTF-8)', "$datadir/params"
  or die "Could not open data file for writing: $!";
print $data_fh <DATA>;
close $data_fh;
close DATA;

# We run import manually instead of with 'use' so that
# these load after the data/params file has been written.
require Bugzilla::Test::MockDB;
Bugzilla::Test::MockDB->import;
require Bugzilla::Test::MockParams;
Bugzilla::Test::MockParams->import;

# Read file back as a Perl data structure for comparison
ok(-f "$datadir/params", 'Parameters file exists');
my $s = Safe->new;
$s->rdo("$datadir/params");
my %file_params = %{$s->varglob('param')};
ok(scalar keys %file_params, 'Parameters file read back correctly');

# Make copy of the newly updated database parameters
my %db_params = %{Bugzilla->params};

foreach my $param (
  qw(attachment_storage bitly_token github_client_id honeypot_api_key
     iprepd_client_secret mfa_group phabricator_api_key webhooks_group)
  )
{
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
           'mfa_group' => 'editbugs',
           'phabricator_api_key' => 'PHABRICATOR_API_KEY',
           'webhooks_group' => 'editbugs',
         );
