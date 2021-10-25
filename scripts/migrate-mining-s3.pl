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

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Product;
use Bugzilla::Report::S3;

use Pod::Usage;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($source, $dest) = @ARGV;

if ( !$source
  || !$dest
  || ($source ne 's3' && $source ne 'file')
  || ($dest ne 's3' && $dest ne 'file')
  || $source eq $dest)
{
  pod2usage({-message => "Missing or incorrect parameters\n", -verbose => 2});
}

my $params = Bugzilla->params;
foreach my $param (
  qw(s3_mining_access_key_id s3_mining_secret_access_key s3_mining_bucket))
{
  $params->{$param}
    || pod2usage(
    "S3 is not configured correctly. Check your settings for 's3_mining_access_key_id',\n"
      . "'s3_mining_secret_access_key' and 's3_mining_bucket'.\n");
}

print STDERR <<"EOF";
About to copy mining data from data/mining/* to or from an AWS S3 bucket.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc;

my $s3 = Bugzilla::Report::S3->new;

my @product_names = map { $_->name } Bugzilla::Product->get_all();
my $mining_dir = bz_locations()->{'datadir'} . '/mining';

foreach my $product ('-All-', @product_names) {
  my $file_product = $product;
  $file_product =~ s/\//-/gs;
  my $file = join '/', $mining_dir, $file_product;

  my $chart_data = '';

  # Load chart data from S3
  if ($source eq 's3') {
    if (!$s3->data_exists($product)) {
      print "Mining data for '$product' does not exist in S3.\n";
      next;
    }
    $chart_data = $s3->get_data($product);
  }

  # Load chart data from filesystem
  if ($source eq 'file') {
    local $/ = undef;
    if (!-f $file) {
      print "Mining data for '$product' does not exist on filesystem.\n";
      next;
    }
    open my $data_fh, '<:encoding(UTF-8)', $file
      or ThrowCodeError('chart_file_fail', {filename => $file});
    $chart_data = <$data_fh>;
    close $data_fh or ThrowCodeError('chart_file_fail', {filename => $file});
  }

  # Save chart data to S3
  if ($dest eq 's3') {
    $s3->set_data($product, $chart_data);
  }

  # Save chart data to filesystem
  if ($dest eq 'file') {
    local $/ = undef;
    open my $data_fh, '>:encoding(UTF-8)', $file
      or ThrowCodeError('chart_file_fail', {'filename' => $file});
    print $data_fh $chart_data;
    close $data_fh or ThrowCodeError('chart_file_fail', {'filename' => $file});
  }

  print "Mining data for '$product' migrated.\n";
}

__END__

=head1 NAME

migrate-mining-s3.pl - Copy the mining data files from data/mining/* the a AWS S3 bucket

=head1 SYNOPSIS

  ./migrate-mining-s3.pl source destination

'source' can either be 's3' or 'file'. Same for 'destination'.

=head1 DESCRIPTION

This script migrates data from or to AWS S3. Historically mining data files were stored in
data/mining/* with each file named after a product. Bugzilla can now be configured to store
the mining data in S3 getting rid of the need for a shared file system when using multiple
web heads.

Make sure 's3_mining_access_key_id', 's3_mining_secret_access_key' and 's3_mining_bucket'
system parameters are all set with correct values for AWS S3.

Note: This will not delete the mining files and that will need to be done
manually. If copying from 's3' to 'file', you may want to back up the old
files first as they will be overwritten.
