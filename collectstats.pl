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

use Getopt::Long qw(:config bundling);
use Pod::Usage;
use List::Util qw(first);
use Cwd;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Install::Filesystem qw(fix_dir_permissions);
use Bugzilla::Product;
use Bugzilla::Report::Net;
use Bugzilla::Search;
use Bugzilla::User;
use Bugzilla::Util;

my %switch;
GetOptions(\%switch, 'help|h', 'regenerate');

# Print the help message if that switch was selected.
pod2usage({-verbose => 1, -exitval => 1}) if $switch{'help'};

# Turn off output buffering (probably needed when displaying output feedback
# in the regenerate mode).
$| = 1;

my $datadir = bz_locations()->{'datadir'};

my $dbh = Bugzilla->switch_to_shadow_db();

# As we can now customize statuses and resolutions, looking at the current list
# of legal values only is not enough as some now removed statuses and resolutions
# may have existed in the past, or have been renamed. We want them all.
my $fields = {};
foreach my $field ('bug_status', 'resolution') {
  my $values     = get_legal_field_values($field);
  my $old_values = $dbh->selectcol_arrayref(
    "SELECT bugs_activity.added
                                FROM bugs_activity
                          INNER JOIN fielddefs
                                  ON fielddefs.id = bugs_activity.fieldid
                           LEFT JOIN $field
                                  ON $field.value = bugs_activity.added
                               WHERE fielddefs.name = ?
                                 AND $field.id IS NULL

                               UNION

                              SELECT bugs_activity.removed
                                FROM bugs_activity
                          INNER JOIN fielddefs
                                  ON fielddefs.id = bugs_activity.fieldid
                           LEFT JOIN $field
                                  ON $field.value = bugs_activity.removed
                               WHERE fielddefs.name = ?
                                 AND $field.id IS NULL", undef, ($field, $field)
  );

  push(@$values, @$old_values);
  $fields->{$field} = $values;
}

my @statuses    = @{$fields->{'bug_status'}};
my @resolutions = @{$fields->{'resolution'}};

# Exclude "" from the resolution list.
@resolutions = grep {$_} @resolutions;

# --regenerate was taking an enormous amount of time to query everything
# per bug, per day. Instead, we now just get all the data out of the DB
# at once and stuff it into some data structures.
my (%bug_status, %bug_resolution, %removed);
if ($switch{'regenerate'}) {
  %bug_resolution = @{
    $dbh->selectcol_arrayref('SELECT bug_id, resolution FROM bugs',
      {Columns => [1, 2]})
  };
  %bug_status = @{
    $dbh->selectcol_arrayref('SELECT bug_id, bug_status FROM bugs',
      {Columns => [1, 2]})
  };

  my $removed_sth = $dbh->prepare(
        q{SELECT bugs_activity.bug_id, bugs_activity.removed,}
      . $dbh->sql_to_days('bugs_activity.bug_when')
      . q{ FROM bugs_activity
           WHERE bugs_activity.fieldid = ?
        ORDER BY bugs_activity.bug_when}
  );

  %removed = (bug_status => {}, resolution => {});
  foreach my $field (qw(bug_status resolution)) {
    my $field_id = Bugzilla::Field->check($field)->id;
    my $rows     = $dbh->selectall_arrayref($removed_sth, undef, $field_id);
    my $hash     = $removed{$field};
    foreach my $row (@$rows) {
      my ($bug_id, $removed, $when) = @$row;
      $hash->{$bug_id} ||= [];
      push(@{$hash->{$bug_id}}, {when => int($when), removed => $removed});
    }
  }
}

my $tstart = time;

my @myproducts = Bugzilla::Product->get_all;
unshift(@myproducts, "-All-");

my $dir = "$datadir/mining";
if (!-d $dir) {
  mkdir $dir or die "mkdir $dir failed: $!";
  fix_dir_permissions($dir);
}

foreach (@myproducts) {
  if ($switch{'regenerate'}) {
    regenerate_stats($dir, $_, \%bug_resolution, \%bug_status, \%removed);
  }
  else {
    &collect_stats($dir, $_);
  }
}

# Fix permissions for all files in mining/.
fix_dir_permissions($dir);

my $tend = time;

# Uncomment the following line for performance testing.
#print "Total time taken " . delta_time($tstart, $tend) . "\n";

CollectSeriesData();

sub collect_stats {
  my $dir     = shift;
  my $product = shift;
  my $when    = localtime(time);
  my $dbh     = Bugzilla->dbh;

  my $product_id;
  if (ref $product) {
    $product_id = $product->id;
    $product    = $product->name;
  }

  # NB: Need to mangle the product for the filename, but use the real
  # product name in the query
  my $file_product = $product;
  $file_product =~ s/\//-/gs;
  my $file = join '/', $dir, $file_product;

  # if the data exists, get the old status and resolution list for that product.
  my $s3 = Bugzilla::Report::Net->new;
  my ($data, $recreate);
  if (($s3->is_enabled && $s3->data_exists($product)) || -f $file) {
    ($data, $recreate) = get_old_data($product);
  }

  # Now collect current data.
  my @row        = (today());
  my $status_sql = q{SELECT COUNT(*) FROM bugs WHERE bug_status = ?};
  my $reso_sql   = q{SELECT COUNT(*) FROM bugs WHERE resolution = ?};

  if ($product ne '-All-') {
    $status_sql .= q{ AND product_id = ?};
    $reso_sql   .= q{ AND product_id = ?};
  }

  my $sth_status = $dbh->prepare($status_sql);
  my $sth_reso   = $dbh->prepare($reso_sql);

  my @values;
  foreach my $status (@statuses) {
    @values = ($status);
    push(@values, $product_id) if ($product ne '-All-');
    my $count = $dbh->selectrow_array($sth_status, undef, @values);
    push(@row, $count);
  }
  foreach my $resolution (@resolutions) {
    @values = ($resolution);
    push(@values, $product_id) if ($product ne '-All-');
    my $count = $dbh->selectrow_array($sth_reso, undef, @values);
    push(@row, $count);
  }

  my $chart_data = '';
  if ($s3->is_enabled || !-f $file || $recreate) {
    my $fields = join('|', ('DATE', @statuses, @resolutions));
    $chart_data = <<"FIN";
# Bugzilla Daily Bug Stats
#
# Do not edit me! This file is generated.
#
# fields: $fields
# Product: $product
# Created: $when
FIN

    foreach my $data (@{$data}) {
      $chart_data .= join('|',
        map { defined $data->{$_} ? $data->{$_} : '' }
          ('DATE', @statuses, @resolutions))
        . "\n";
    }
  }
  $chart_data .= (join '|', @row) . "\n";

  if ($s3->is_enabled) {
    $s3->set_data($product, $chart_data);
  }
  else {
    # If statuses or resolutions were different, then we have to recreate the data file.
    my $data_fh;
    if (!-f $file || $recreate) {
      open $data_fh, '>:encoding(UTF-8)', $file
        or ThrowCodeError('chart_file_fail', {'filename' => $file});
    }
    else {
      open $data_fh, '>>:encoding(UTF-8)', $file
        or ThrowCodeError('chart_file_fail', {'filename' => $file});
    }

    print $data_fh $chart_data;
    close $data_fh or ThrowCodeError('chart_file_fail', {'filename' => $file});
  }
}

sub get_old_data {
  my $product      = shift;
  my $file_product = $product;
  $file_product =~ s/\//-/gs;
  my $file = join '/', $dir, $file_product;

  # First try to get the data from S3 if enabled
  my $chart_data = '';
  my $s3 = Bugzilla::Report::Net->new;
  if ($s3->is_enabled) {
    $chart_data = $s3->get_data($product) if $s3->data_exists($product);
    if (!$chart_data) {
      ThrowCodeError('net_mining_get_failed');
    }
  }
  else {
    local $/;
    open my $data_fh, '<:encoding(UTF-8)', $file
      or ThrowCodeError('chart_file_fail', {filename => $file});
    $chart_data = <$data_fh>;
    close $data_fh or ThrowCodeError('chart_file_fail', {filename => $file});
  }

  my @data     = ();
  my @columns  = ();
  my $recreate = 0;
  foreach my $line (split /\n/, $chart_data) {
    chomp $line;
    next unless $line;
    if ($line =~ /^# fields?:\s*(.+)\s*$/) {
      @columns = split(/\|/, $1);

      # Compare this list with @statuses and @resolutions.
      # If they are identical, then we can safely append new data
      # to the end of the file; else we have to recreate it.
      my @new_cols = ($columns[0], @statuses, @resolutions);
      if (scalar(@columns) == scalar(@new_cols)) {
        for (0 .. $#columns) {
          $recreate = 1 if ($columns[$_] ne $new_cols[$_]);
        }
      }
    }
    next if ($line =~ /^#/);    # Ignore comments.
    my @line = split /\|/, $line;
    my %data;
    foreach my $column (@columns) {
      $data{$column} = shift @line;
    }
    push @data, \%data;
  }

  return (\@data, $recreate);
}

# This regenerates all statistics from the database.
sub regenerate_stats {
  my ($dir, $product, $bug_resolution, $bug_status, $removed) = @_;

  my $dbh    = Bugzilla->dbh;
  my $when   = localtime(time());
  my $tstart = time();

  # NB: Need to mangle the product for the filename, but use the real
  # product name in the query
  if (ref $product) {
    $product = $product->name;
  }
  my $file_product = $product;
  $file_product =~ s/\//-/gs;
  my $file = join '/', $dir, $file_product;

  my $and_product  = "";
  my $from_product = "";

  my @values = ();
  if ($product ne '-All-') {
    $and_product  = q{ AND products.name = ?};
    $from_product = q{ INNER JOIN products
                          ON bugs.product_id = products.id};
    push(@values, $product);
  }

  # Determine the start date from the date the first bug in the
  # database was created, and the end date from the current day.
  # If there were no bugs in the search, return early.
  my $query
    = q{SELECT }
    . $dbh->sql_to_days('creation_ts')
    . q{ AS start_day, }
    . $dbh->sql_to_days('current_date')
    . q{ AS end_day, }
    . $dbh->sql_to_days("'1970-01-01'")
    . qq{ FROM bugs $from_product
                   WHERE }
    . $dbh->sql_to_days('creation_ts') . qq{ IS NOT NULL $and_product
                ORDER BY start_day } . $dbh->sql_limit(1);
  my ($start, $end, $base) = $dbh->selectrow_array($query, undef, @values);

  if (!defined $start) {
    return;
  }

  my $fields     = join('|', ('DATE', @statuses, @resolutions));
  my $chart_data = <<"FIN";
# Bugzilla Daily Bug Stats
#
# Do not edit me! This file is generated.
#
# fields: $fields
# Product: $product
# Created: $when
FIN

  # For each day, generate a line of statistics.
  my $total_days = $end - $start;
  my @bugs;
  for (my $day = $start + 1; $day <= $end; $day++) {

    # Some output feedback
    my $percent_done = ($day - $start - 1) * 100 / $total_days;
    printf "\rRegenerating $product \[\%.1f\%\%]", $percent_done;

    # Get a list of bugs that were created the previous day, and
    # add those bugs to the list of bugs for this product.
    $query = qq{SELECT bug_id
                        FROM bugs $from_product
                        WHERE bugs.creation_ts < }
      . $dbh->sql_from_days($day - 1)
      . q{ AND bugs.creation_ts >= }
      . $dbh->sql_from_days($day - 2)
      . $and_product
      . q{ ORDER BY bug_id};

    my $bug_ids = $dbh->selectcol_arrayref($query, undef, @values);
    push(@bugs, @$bug_ids);

    my %bugcount;
    foreach (@statuses)    { $bugcount{$_} = 0; }
    foreach (@resolutions) { $bugcount{$_} = 0; }

    # Get information on bug states and resolutions.
    for my $bug (@bugs) {
      my $status
        = _get_value($removed->{'bug_status'}->{$bug}, $bug_status, $day, $bug);

      if (defined $bugcount{$status}) {
        $bugcount{$status}++;
      }

      my $resolution
        = _get_value($removed->{'resolution'}->{$bug}, $bug_resolution, $day, $bug);

      if (defined $bugcount{$resolution}) {
        $bugcount{$resolution}++;
      }
    }

    # Generate a line of output containing the date and counts
    # of bugs in each state.
    my $date = sqlday($day, $base);
    $chart_data .= "$date";
    foreach (@statuses)    { $chart_data .= "|$bugcount{$_}"; }
    foreach (@resolutions) { $chart_data .= "|$bugcount{$_}"; }
    $chart_data .= "\n";

    # Finish up output feedback for this product.
    my $tend = time;
    print "\rRegenerating $product \[100.0\%] - "
      . delta_time($tstart, $tend) . "\n";
  }

  # First try to set the data in S3 if enabled
  my $s3 = Bugzilla::Report::Net->new;
  if ($s3->is_enabled) {
    $s3->set_data($product, $chart_data);
  }
  else {
    open my $data_fh, ">:encoding(UTF-8)", $file or ThrowCodeError();
    print $data_fh $chart_data;
    close $data_fh or ThrowCodeError();
  }
}

# A helper for --regenerate.
# For each bug that exists on a day, we determine its status/resolution
# at the beginning of the day.  If there were no status/resolution
# changes on or after that day, the status was the same as it
# is today (the "current" value).  Otherwise, the status was equal to the
# first "previous value" entry in the bugs_activity table for that
# bug made on or after that day.
sub _get_value {
  my ($removed, $current, $day, $bug) = @_;

  # Get the first change that's on or after this day.
  my $item = first { $_->{when} >= $day } @{$removed || []};

  # If there's no change on or after this day, then we just return the
  # current value.
  return $item ? $item->{removed} : $current->{$bug};
}

sub today {
  my ($dom, $mon, $year) = (localtime(time))[3, 4, 5];
  return sprintf "%04d%02d%02d", 1900 + $year, ++$mon, $dom;
}

sub today_dash {
  my ($dom, $mon, $year) = (localtime(time))[3, 4, 5];
  return sprintf "%04d-%02d-%02d", 1900 + $year, ++$mon, $dom;
}

sub sqlday {
  my ($day, $base) = @_;
  $day = ($day - $base) * 86400;
  my ($dom, $mon, $year) = (gmtime($day))[3, 4, 5];
  return sprintf "%04d%02d%02d", 1900 + $year, ++$mon, $dom;
}

sub delta_time {
  my $tstart  = shift;
  my $tend    = shift;
  my $delta   = $tend - $tstart;
  my $hours   = int($delta / 3600);
  my $minutes = int($delta / 60) - ($hours * 60);
  my $seconds = $delta - ($minutes * 60) - ($hours * 3600);
  return sprintf("%02d:%02d:%02d", $hours, $minutes, $seconds);
}

sub CollectSeriesData {

  # We need some way of randomizing the distribution of series, such that
  # all of the series which are to be run every 7 days don't run on the same
  # day. This is because this might put the server under severe load if a
  # particular frequency, such as once a week, is very common. We achieve
  # this by only running queries when:
  # (days_since_epoch + series_id) % frequency = 0. So they'll run every
  # <frequency> days, but the start date depends on the series_id.
  my $days_since_epoch = int(time() / (60 * 60 * 24));
  my $today            = today_dash();

  # We save a copy of the main $dbh and then switch to the shadow and get
  # that one too. Remember, these may be the same.
  my $dbh        = Bugzilla->switch_to_main_db();
  my $shadow_dbh = Bugzilla->switch_to_shadow_db();

  my $serieses = $dbh->selectall_hashref(
    "SELECT series_id, query, creator "
      . "FROM series "
      . "WHERE frequency != 0 AND "
      . "MOD(($days_since_epoch + series_id), frequency) = 0",
    "series_id"
  );

  # We prepare the insertion into the data table, for efficiency.
  my $sth
    = $dbh->prepare("INSERT INTO series_data "
      . "(series_id, series_date, series_value) "
      . "VALUES (?, "
      . $dbh->quote($today)
      . ", ?)");

  # We delete from the table beforehand, to avoid SQL errors if people run
  # collectstats.pl twice on the same day.
  my $deletesth = $dbh->prepare(
    "DELETE FROM series_data
                                   WHERE series_id = ? AND series_date = "
      . $dbh->quote($today)
  );

  foreach my $series_id (keys %$serieses) {

    # We set up the user for Search.pm's permission checking - each series
    # runs with the permissions of its creator.
    my $user = new Bugzilla::User($serieses->{$series_id}->{'creator'});

    # Load the params from the stored query into the current CGI instance
    my $cgi = Bugzilla->cgi;
    $cgi->parse_params($serieses->{$series_id}->{'query'});

    # This will be used as user_agent in Search.pm
    $cgi->script_name('collectstats.pl');

    # Do not die if Search->new() detects invalid data, such as an obsolete
    # login name or a renamed product or component, etc.
    my $data;
    eval {
      my $search = new Bugzilla::Search(
        'params'          => scalar $cgi->Vars,
        'fields'          => ["bug_id"],
        'allow_unlimited' => 1,
        'user'            => $user
      );
      $data = $search->data;
    };

    if (!$@) {

      # We need to count the returned rows. Without subselects, we can't
      # do this directly in the SQL for all queries. So we do it by hand.
      my $count = scalar(@$data) || 0;

      $deletesth->execute($series_id);
      $sth->execute($series_id, $count);
    }
  }
}

__END__

=head1 NAME

collectstats.pl - Collect data about Bugzilla bugs.

=head1 SYNOPSIS

 ./collectstats.pl [--regenerate] [--help]

Collects data about bugs to be used in Old and New Charts.

=head1 OPTIONS

=over

=item B<--help>

Print this help page.

=item B<--regenerate>

Recreate all the data about bugs, from day 1. This option is only relevant
for Old Charts, and has no effect for New Charts.
This option will overwrite all existing collected data and can take a huge
amount of time. You normally don't need to use this option (do not use it
in a cron job).

=back

=head1 DESCRIPTION

This script collects data about all bugs for Old Charts, triaged by product
and by bug status and resolution. It also collects data for New Charts, based
on existing series. For New Charts, data is only collected once a series is
defined; this script cannot recreate data prior to this date.
