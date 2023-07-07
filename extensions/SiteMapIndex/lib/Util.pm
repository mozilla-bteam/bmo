# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Sitemap Bugzilla Extension.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>
#   Dave Lawrence <dkl@mozilla.com>


package Bugzilla::Extension::SiteMapIndex::Util;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(
  bug_is_ok_to_index
  generate_sitemap
);

use Bugzilla;
use Bugzilla::S3;
use Bugzilla::Util qw(datetime_from url_quote);

use Bugzilla::Extension::SiteMapIndex::Constants;

use Scalar::Util       qw(blessed);
use IO::Compress::Gzip qw(gzip $GzipError);

sub too_young_date {
  my $hours_ago = DateTime->now(time_zone => Bugzilla->local_timezone);
  $hours_ago->subtract(hours => SITEMAP_DELAY);
  return $hours_ago;
}

sub bug_is_ok_to_index {
  my ($bug) = @_;
  return 1 unless blessed($bug) && $bug->isa('Bugzilla::Bug') && !$bug->{error};
  my $creation_ts = datetime_from($bug->creation_ts);
  return ($creation_ts && $creation_ts lt too_young_date()) ? 1 : 0;
}

# We put two things in the Sitemap: a list of Browse links for products and links to bugs.
sub generate_sitemap {
  my $index_file = 'sitemap_index.xml';

  # Sitemaps must never contain private data.
  Bugzilla->logout_request();
  my $user     = Bugzilla->user;
  my $products = $user->get_accessible_products;

  my $num_bugs = SITEMAP_MAX - scalar(@$products);

  # We do this date math outside of the database because databases
  # usually do better with a straight comparison value.
  my $hours_ago = too_young_date();

  # We don't use Bugzilla::Bug objects, because this could be a tremendous
  # amount of data, and we only want a little. Also, we only display
  # bugs that are not in any group. We show the last $num_bugs
  # most-recently-updated bugs.
  my $dbh     = Bugzilla->dbh;
  my $bug_sth = $dbh->prepare(
    'SELECT bugs.bug_id, bugs.delta_ts
           FROM bugs
                LEFT JOIN bug_group_map ON bugs.bug_id = bug_group_map.bug_id
          WHERE bug_group_map.bug_id IS NULL AND creation_ts < ?
        ' . $dbh->sql_limit($num_bugs, '?')
  );

  my $filecount = 1;
  my $filelist  = [];
  my $offset    = 0;

  while (1) {
    my $bugs = [];

    $bug_sth->execute($hours_ago, $offset);

    while (my ($bug_id, $delta_ts) = $bug_sth->fetchrow_array()) {
      push(@$bugs, {bug_id => $bug_id, delta_ts => $delta_ts});
    }

    last if !@$bugs;

    # We only need the product links in the first sitemap file
    $products = [] if $filecount > 1;

    push @$filelist, _generate_sitemap_file($filecount, $products, $bugs);

    $filecount++;
    $offset += $num_bugs;
  }

  # Generate index file
  return _generate_sitemap_index($filelist);
}

sub _generate_sitemap_index {
  my ($filelist) = @_;

  my $dbh       = Bugzilla->dbh;
  my $timestamp = $dbh->selectrow_array(
    "SELECT " . $dbh->sql_date_format('NOW()', '%Y-%m-%d'));

  my $index_xml = <<END;
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
END

  my $sitemap_url
    = 'https://'
    . Bugzilla->params->{sitemapindex_s3_bucket} . '.s3-'
    . Bugzilla->params->{sitemapindex_aws_region}
    . '.amazonaws.com';

  use Bugzilla::Logging;
  DEBUG($sitemap_url);

  foreach my $filename (@$filelist) {
    $index_xml .= "
  <sitemap>
    <loc>$sitemap_url/$filename</loc>
    <lastmod>$timestamp</lastmod>
  </sitemap>
";
  }

  $index_xml .= <<END;
</sitemapindex>
END

  # Upload index file to s3
  _upload_s3('sitemap_index.xml', $index_xml);

  return 1;
}

sub _generate_sitemap_file {
  my ($filecount, $products, $bugs) = @_;

  my $bug_url = Bugzilla->localconfig->urlbase . 'show_bug.cgi?id=';
  my $product_url
    = Bugzilla->localconfig->urlbase . 'describecomponents.cgi?product=';

  my $sitemap_xml = <<END;
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
END

  foreach my $product (@$products) {
    $sitemap_xml .= "
  <url>
    <loc>" . $product_url . url_quote($product->name) . "</loc>
    <changefreq>daily</changefreq>
    <priority>0.4</priority>
  </url>
";
  }

  foreach my $bug (@$bugs) {
    $sitemap_xml .= "
  <url>
    <loc>" . $bug_url . $bug->{bug_id} . "</loc>
    <lastmod>" . datetime_from($bug->{delta_ts}, 'UTC')->iso8601 . 'Z' . "</lastmod>
  </url>
";
  }

  $sitemap_xml .= <<END;
</urlset>
END

  # Write the compressed sitemap data to a variable and then upload to s3
  my $gzipped_data;
  gzip \$sitemap_xml => \$gzipped_data || die "gzip failed: $GzipError\n";

  my $filename = "sitemap$filecount.xml.gz";
  _upload_s3($filename, $gzipped_data);

  return $filename;
}

sub _upload_s3 {
  my ($filename, $data) = @_;
  return;
  my $s3 = Bugzilla::S3->new({
    aws_access_key_id     => Bugzilla->params->{sitemapindex_aws_client_id},
    aws_secret_access_key => Bugzilla->params->{sitemapindex_aws_client_secret},
    secure                => 1,
    retry                 => 1,
  });
  my $bucket = $s3->bucket(Bugzilla->params->{sitemapindex_s3_bucket});
  $bucket->delete_key($filename) || die $bucket->errstr;
  $bucket->add_key($filename, $data) || die $bucket->errstr;
}

1;
