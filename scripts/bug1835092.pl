#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License,  v. 2.0. If a copy of the MPL was not distributed with this
# file,  You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses",  as
# defined by the Mozilla Public License,  v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util qw(trim);

use Mojo::File qw(path);
use Text::CSV_XS;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

my $csv_file = shift;
my @csv_data = split /\n/, path($csv_file)->slurp;
scalar @csv_data || die "Could not load CSV data from $csv_file\n";

$dbh->bz_start_transaction();

my $insert_sth
  = $dbh->prepare("INSERT INTO longdescs_tags_url (tag, url) VALUES (?, ?)");

my $csv = Text::CSV_XS->new();
foreach my $line (@csv_data) {
  $csv->parse($line);
  my @values = $csv->fields();
  next if !@values;
  my ($tag, $url) = @values;

  $tag = trim($tag);
  $url = trim($url);

  # Skip if not an url
  if ($url !~ /^https?:/) {
    print "URL '$url' invalid...skipping\n";
    next;
  }

  # Do not populate if already present
  my $exists
    = $dbh->selectrow_array('SELECT 1 FROM longdescs_tags_url WHERE tag = ?',
    undef, $tag);
  if ($exists) {
    print "$tag => $url exists...skipping\n";
    next;
  }

  print "Adding $tag => $url\n";
  $insert_sth->execute($tag, $url);
}

$dbh->bz_commit_transaction();


