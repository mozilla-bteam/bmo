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
use Bugzilla::Error;
use Bugzilla::Report::S3;
use Bugzilla::Status;
use Bugzilla::Util;

use Digest::SHA qw(hmac_sha256_base64);
use File::Basename;
use MIME::Base64 qw(encode_base64);

# If we're using bug groups for products, we should apply those restrictions
# to viewing reports, as well.  Time to check the login in that case.
my $user     = Bugzilla->login();
my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

if (!Bugzilla->feature('old_charts')) {
  ThrowCodeError('feature_disabled', {feature => 'old_charts'});
}

my $dir          = bz_locations()->{'datadir'} . "/mining";
my $product_name = $cgi->param('product') || '';

Bugzilla->switch_to_shadow_db();

if (!$product_name) {
  my %default_sel = map { $_ => 1 } BUG_STATE_OPEN;

  my @datasets;
  my @data = get_data($dir);

  foreach my $dataset (@data) {
    my $datasets = {};
    $datasets->{'value'}    = $dataset;
    $datasets->{'selected'} = $default_sel{$dataset} ? 1 : 0;
    push(@datasets, $datasets);
  }

  # We only want those products that the user has permissions for.
  my @myproducts = ('-All-');

  # Extract product names from objects and add them to the list.
  push(@myproducts, map { $_->name } @{$user->get_selectable_products});

  $vars->{'datasets'} = \@datasets;
  $vars->{'products'} = \@myproducts;

  print $cgi->header();
}
else {
# For security and correctness, validate the value of the "product" form variable.
# Valid values are those products for which the user has permissions which appear
# in the "product" drop-down menu on the report generation form.
  my ($product)
    = grep { $_->name eq $product_name } @{$user->get_selectable_products};
  ($product || $product_name eq '-All-')
    || ThrowUserError('invalid_product_name', {product => $product_name});

  # Product names can change over time. Their ID cannot; so use the ID
  # to generate the filename.
  my $prod_id = $product ? $product->id : 0;

  # Make sure there is something to plot.
  my @datasets = $cgi->param('datasets');
  scalar(@datasets) || ThrowUserError('missing_datasets');

  if (grep { $_ !~ /^[A-Za-z0-9:_-]+$/ } @datasets) {
    ThrowUserError('invalid_datasets', {'datasets' => \@datasets});
  }

  my $png = generate_chart($dir, $product, \@datasets);
  $vars->{'image_data'} = encode_base64($png);

  print $cgi->header(
    -Content_Disposition => 'inline; filename=bugzilla_report.html');
}

$template->process('reports/old-charts.html.tmpl', $vars)
  || ThrowTemplateError($template->error());

#####################
#    Subroutines    #
#####################

sub get_data {
  my $dir = shift;
  my $chart_data;

  # First try to get the data from S3 if enabled
  my $s3 = Bugzilla::Report::S3->new;
  if ($s3->is_enabled) {
    $chart_data = $s3->get_data('-All-') if $s3->data_exists('-All-');
  }
  else {
    local $/;
    open my $data_fh, '<:encoding(UTF-8)',
      "$dir/-All-" or ThrowCodeError('chart_file_fail', {filename => "$dir/-All-"});
    $chart_data = <$data_fh>;
    close $data_fh or ThrowCodeError('chart_file_fail', {filename => "$dir/-All-"});
  }

  $chart_data
    || ThrowCodeError('chart_data_not_generated', {'product' => '-All-'});

  my @datasets;
  foreach my $line (split /\n/, $chart_data) {
    if ($line =~ /^# fields?: (.+)\s*$/) {
      @datasets = grep { !/date/i } (split /\|/, $1);
      last;
    }
  }

  return @datasets;
}

sub generate_chart {
  my ($dir, $product, $datasets) = @_;
  $product = $product ? $product->name : '-All-';
  my @fields;
  my @labels    = qw(DATE);
  my %datasets  = map { $_ => 1 } @$datasets;
  my %data      = ();
  my $data_file = $product;
  $data_file =~ s/\//-/gs;
  $data_file = $dir . '/' . $data_file;
  my $chart_data;

  # First try to get the data from S3 if enabled
  my $s3 = Bugzilla::Report::S3->new;
  if ($s3->is_enabled) {
    $chart_data = $s3->get_data($product) if $s3->data_exists($product);
  }
  else {
    local $/;
    open my $fh, '<:encoding(UTF-8)',
      $data_file or ThrowCodeError('chart_file_fail', {filename => $data_file});
    $chart_data = <$fh>;
    close $fh or ThrowCodeError('chart_file_fail', {filename => $data_file});
  }

  $chart_data
    || ThrowCodeError('chart_data_not_generated', {'product' => $product});

  foreach my $line (split /\n/, $chart_data) {
    chomp $line;
    next unless $line;
    if ($line =~ /^#/) {
      if ($line =~ /^# fields?: (.*)\s*$/) {
        @fields = split /\||\r/, $1;
        foreach my $field (@fields) {
          $data{$field} ||= [];
        }
        unless ($fields[0] =~ /date/i) {
          ThrowCodeError('chart_datafile_corrupt', {file => $data_file});
        }
        push @labels, grep { $datasets{$_} } @fields;
      }
      next;
    }

    unless (@fields) {
      ThrowCodeError('chart_datafile_corrupt', {'file' => $data_file});
    }

    my @line = split /\|/, $line;
    my $date = $line[0];
    my ($yy, $mm, $dd) = $date =~ /^\d{2}(\d{2})(\d{2})(\d{2})$/;
    push @{$data{DATE}}, "$mm/$dd/$yy";

    for my $i (1 .. $#fields) {
      my $field = $fields[$i];
      if (!defined $line[$i] or $line[$i] eq '') {

        # no data point given, don't plot (this will probably
        # generate loads of Chart::Base warnings, but that's not
        # our fault.)
        push @{$data{$field}}, undef;
      }
      else {
        push @{$data{$field}}, $line[$i];
      }
    }
  }

  shift @labels;

  if (!@{$data{DATE}}) {
    ThrowUserError('insufficient_data_points');
  }

  my $img = Chart::Lines->new(800, 600);
  my $i   = 0;

  my $MAXTICKS = 20;    # Try not to show any more x ticks than this.
  my $skip     = 1;
  if (@{$data{DATE}} > $MAXTICKS) {
    $skip = int((@{$data{DATE}} + $MAXTICKS - 1) / $MAXTICKS);
  }

  my %settings = (
    "title"           => "Status Counts for $product",
    "x_label"         => "Dates",
    "y_label"         => "Bug Counts",
    "legend_labels"   => \@labels,
    "skip_x_ticks"    => $skip,
    "y_grid_lines"    => "true",
    "grey_background" => "false",
    "colors"          => {

      # default dataset colors are too alike
      dataset4 => [0, 0, 0],    # black
    },
  );

  $img->set(%settings);
  return $img->scalar_png([@data{('DATE', @labels)}]);
}
