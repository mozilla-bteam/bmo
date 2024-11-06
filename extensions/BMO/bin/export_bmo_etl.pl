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
use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Flag;
use Bugzilla::User;

use HTTP::Headers;
use HTTP::Request;
use IO::Compress::Gzip     qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use LWP::UserAgent::Determined;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json false true);
use Mojo::Util qw(getopt);

# BigQuery API cannot handle payloads larger than 10MB so
# we will send data in blocks.
use constant API_BLOCK_COUNT => 1000;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
getopt 't|test' => \my $test, 'v|verbose' => \my $verbose;

if (!Bugzilla->params->{bmo_etl_enabled}) {
  die "BMO ETL not enabled.\n";
}

if (!$test && !Bugzilla->params->{bmo_etl_base_url}) {
  die "BMO ETL base url not defined.\n";
}

# Use replica if available
my $dbh = Bugzilla->switch_to_shadow_db();

my $ua = LWP::UserAgent::Determined->new(
  agent                 => 'Bugzilla',
  keep_alive            => 10,
  requests_redirectable => [qw(GET HEAD DELETE PUT)],
);
$ua->timing('1,2,4,8,16,32');
$ua->timeout(30);
if (my $proxy = Bugzilla->params->{proxy_url}) {
  $ua->proxy(['https', 'http'], $proxy);
}

# This date will be added to each object as it is being sent
my $snapshot_date = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
my $file_snapshot = $snapshot_date;
$file_snapshot =~ s/[\s:-]+/_/g;

### Bugs

my $table_name = 'bugs';
my $rows       = $dbh->selectall_arrayref(
  'SELECT bug_id AS id, delta_ts AS modification_time FROM bugs ORDER BY bug_id',
  {Slice => {}}
);

my $total = scalar @{$rows};
my $count = 0;

print "Processing $total bugs.\n" if $verbose;

my @results = ();
foreach my $row (@{$rows}) {

  # First check to see if we have a cached version with the same modification date
  my $data = get_cache($row->{id}, $table_name, $row->{modification_time});
  if (!$data) {
    print "$table_name id " . $row->{id} . " not found in cache.\n" if $verbose;

    my $obj = Bugzilla::Bug->new($row->{id});

    $data = {
      id              => $obj->id,
      assignee_id     => $obj->assigned_to->id,
      url             => $obj->bug_file_loc,
      severity        => $obj->bug_severity,
      status          => $obj->bug_status,
      type            => $obj->bug_type,
      crash_signature => $obj->cf_crash_signature,
      component       => $obj->component,
      creation_ts     => $obj->creation_ts,
      updated_ts      => $obj->delta_ts,
      op_sys          => $obj->op_sys,
      priority        => $obj->priority,
      product         => $obj->product,
      platform        => $obj->rep_platform,
      reporter_id     => $obj->reporter->id,
      resolution      => $obj->resolution,
      summary         => $obj->short_desc,
      whiteboard      => $obj->status_whiteboard,
      milestone       => $obj->target_milestone,
      version         => $obj->version,
      team_name       => $obj->component_obj->team_name,
      classification  => $obj->classification,
      comment_count   => $obj->comment_count,
      vote_count      => $obj->votes,
      group           => (join ',', map { $_->name } @{$obj->groups}),
      is_public       => (scalar @{$obj->groups_in} ? true : false),
      cc_count        => scalar @{$obj->cc || []},
    };

    # Store a copy of the data for use in later executions
    store_cache($obj->id, $table_name, $obj->delta_ts, $data);
  }

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Attachments

$table_name = 'attachments';
$rows       = $dbh->selectall_arrayref(
  'SELECT attach_id AS id, modification_time FROM attachments ORDER BY attach_id',
  {Slice => {}}
);

$total = scalar @{$rows};
$count = 0;

print "Processing $total attachments.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {

  # First check to see if we have a cached version with the same modification date
  my $data = get_cache($row->{id}, $table_name, $row->{modification_time});
  if (!$data) {
    print "$table_name id "
      . $row->{id}
      . ' with time '
      . $row->{modification_time}
      . " not found in cache.\n"
      if $verbose;

    my $obj = Bugzilla::Attachment->new($row->{id});

    $data = {
      id           => $obj->id,
      bug_id       => $obj->bug_id,
      creation_ts  => $obj->attached,
      description  => $obj->description,
      filename     => $obj->filename,
      content_type => $obj->contenttype,
      updated_ts   => $obj->modification_time,
      submitter_id => $obj->attacher->id,
      is_obsolete  => ($obj->isobsolete ? true : false),
    };

    # Store a new copy of the data for use later
    store_cache($obj->id, $table_name, $obj->modification_time, $data);
  }

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Flags

$table_name = 'flags';
$rows
  = $dbh->selectall_arrayref(
  'SELECT id, modification_date FROM flags ORDER BY id',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total flags.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {

  # First check to see if we have a cached version with the same modification date
  my $data = get_cache($row->{id}, $table_name, $row->{modification_date});
  if (!$data) {
    print "$table_name id " . $row->{id} . " not found in cache.\n" if $verbose;

    my $obj = Bugzilla::Flag->new($row->{id});

    $data = {
      attachment_id => $obj->attach_id,
      bug_id        => $obj->bug_id,
      creation_ts   => $obj->creation_date,
      updated_ts    => $obj->modification_date,
      requestee_id  => $obj->requestee_id,
      setter_id     => $obj->setter_id,
      name          => $obj->type->name,
      value         => $obj->status,
    };

    # Store a new copy of the data for use later
    store_cache($obj->id, $table_name, $obj->modification_date, $data);
  }

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Tracking Flags

$table_name = 'tracking_flags';
$rows       = $dbh->selectall_arrayref(
  'SELECT tracking_flags.name AS name, tracking_flags_bugs.bug_id AS bug_id, tracking_flags_bugs.value AS value
     FROM tracking_flags_bugs
          JOIN tracking_flags
          ON tracking_flags_bugs.tracking_flag_id = tracking_flags.id
    ORDER BY tracking_flags_bugs.bug_id', {Slice => {}}
);

$total = scalar @{$rows};
$count = 0;

print "Processing $total tracking flags.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data
    = {bug_id => $row->{bug_id}, name => $row->{name}, value => $row->{value},};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Keywords

$table_name = 'keywords';
$rows       = $dbh->selectall_arrayref(
  'SELECT bug_id, keyworddefs.name AS name
       FROM keywords
            JOIN keyworddefs
            ON keywords.keywordid = keyworddefs.id
      ORDER BY bug_id', {Slice => {}}
);

$total = scalar @{$rows};
$count = 0;

print "Processing $total keywords.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{bug_id}, keyword => $row->{name},};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### See Also

$table_name = 'see_also';
$rows
  = $dbh->selectall_arrayref(
  'SELECT bug_id, value, class FROM bug_see_also ORDER BY bug_id',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total see also values.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{bug_id},};
  if ($row->{class} =~ /::Local/) {
    $data->{url}
      = Bugzilla->localconfig->urlbase . 'show_bug.cgi?id=' . $row->{value};
  }
  else {
    $data->{url} = $row->{value};
  }

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Mentors

$table_name = 'bug_mentors';
$rows
  = $dbh->selectall_arrayref(
  'SELECT bug_id, user_id FROM bug_mentors ORDER BY bug_id',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total bug mentors.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{bug_id}, user_id => $row->{user_id}};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Dependencies

$table_name = 'bug_dependencies';
$rows
  = $dbh->selectall_arrayref(
  'SELECT blocked, dependson FROM dependencies ORDER BY blocked',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total bug dependency values.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{blocked}, depends_on_id => $row->{dependson}};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Regressions

$table_name = 'bug_regressions';
$rows
  = $dbh->selectall_arrayref('SELECT regresses, regressed_by FROM regressions',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total bug regression values.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{regresses}, regresses_id => $row->{regressed_by},};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Duplicates

$table_name = 'bug_duplicates';
$rows       = $dbh->selectall_arrayref('SELECT dupe, dupe_of FROM duplicates',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total bug duplicate values.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {
  my $data = {bug_id => $row->{dupe}, duplicate_of_id => $row->{dupe_of},};

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

### Users

$table_name = 'users';
$rows
  = $dbh->selectall_arrayref(
  'SELECT userid AS id FROM profiles ORDER BY userid',
  {Slice => {}});

$total = scalar @{$rows};
$count = 0;

print "Processing $total users.\n" if $verbose;

@results = ();
foreach my $row (@{$rows}) {

  # Determine last update timestamp for this user
  # The profiles table does not have its own modification_time field
  # so we have find it from the profiles_activity table and/or audit_log.
  my ($profiles_activity_ts, $profiles_activity_epoch) = $dbh->selectrow_array(
    'SELECT profiles_when, UNIX_TIMESTAMP(profiles_when) FROM profiles_activity WHERE userid = ? ORDER BY profiles_when DESC LIMIT 1',
    undef, $row->{id}
  );
  my ($audit_log_ts, $audit_log_epoch) = $dbh->selectrow_array(
    'SELECT at_time, UNIX_TIMESTAMP(at_time) FROM audit_log WHERE class = \'Bugzilla::User\' AND object_id = ? ORDER BY at_time DESC LIMIT 1',
    undef, $row->{id}
  );

  $profiles_activity_epoch ||= 0;
  $audit_log_epoch         ||= 0;

  my $modification_time;
  if ($audit_log_epoch > $profiles_activity_epoch) {
    $modification_time = $audit_log_ts;
  }
  elsif ($profiles_activity_epoch > $audit_log_epoch) {
    $modification_time = $profiles_activity_ts;
  }

  if ($verbose) {
    print 'Modification time is '
      . ($modification_time ? $modification_time : 'undefined') . "\n";
  }

  # First check to see if we have a cached version with the same modification date
  my $data;
  if ($modification_time) {
    $data = get_cache($row->{id}, $table_name, $modification_time);
  }

  if (!$data) {
    print "$table_name id " . $row->{id} . " not found in cache.\n" if $verbose;

    my $obj = Bugzilla::User->new($row->{id});

    $data = {
      id         => $obj->id,
      last_seen  => $obj->last_seen_date,
      email      => $obj->email,
      nick       => $obj->nick,
      name       => $obj->name,
      ldap_email => $obj->ldap_email,
      is_new     => $obj->is_new,
      is_staff   => ($obj->in_group('mozilla-employee-confidential') ? true : false),
      is_trusted => ($obj->in_group('editbugs')                      ? true : false),
    };

    # Store a new copy of the data for use later
    if ($modification_time) {
      store_cache($obj->id, $table_name, $modification_time, $data);
    }
  }

  push @results, $data;

  $count++;

  # Send the rows to the server if we have a specific sized block'
  # or we are at the last row
  if (scalar @results == API_BLOCK_COUNT || $total == $count) {
    send_data($table_name, \@results, $count);
    @results = ();
  }
}

# Functions

sub get_cache {
  my ($id, $table, $timestamp) = @_;

  print "Retreiving data from $table for $id with time $timestamp.\n" if $verbose;

  # Retrieve compressed JSON from cache table if it exists
  my $gzipped_data = $dbh->selectrow_array(
    'SELECT data FROM bmo_etl_cache WHERE id = ? AND table_name = ? AND snapshot_date = ?',
    undef, $id, $table, $timestamp
  );
  return undef if !$gzipped_data;

  # First uncompress the JSON and then decode it back to Perl data
  my $data;
  gunzip \$gzipped_data => \$data or die "gunzip failed: $GunzipError\n";
  return decode_json($data);
}

sub store_cache {
  my ($id, $table, $timestamp, $data) = @_;

  print "Storing data into $table for $id with time $timestamp.\n" if $verbose;

  # Encode the perl data into JSON
  $data = encode_json($data);

  # Compress the JSON to save space in the DB
  my $gzipped_data;
  gzip \$data => \$gzipped_data or die "gzip failed: $GzipError\n";

  # We need to use the main DB for write operations
  my $main_dbh = Bugzilla->dbh;

  # Clean out outdated JSON
  $main_dbh->do('DELETE FROM bmo_etl_cache WHERE id = ? AND table_name = ?',
    undef, $id, $table);

  # Enter new cached JSON
  $main_dbh->do(
    'INSERT INTO bmo_etl_cache (id, table_name, snapshot_date, data) VALUES (?, ?, ?, ?)',
    undef, $id, $table, $timestamp, $gzipped_data
  );
}

sub send_data {
  my ($table, $all_rows, $current_count) = @_;

  print 'Sending '
    . scalar @{$all_rows}
    . " rows to table $table using BigQuery API\n"
    if $verbose;

  # Add the same snapshot date to every row sent
  foreach my $row (@{$all_rows}) {
    $row->{snapshot_date} = $snapshot_date;
  }

  my $project_id = Bugzilla->params->{bmo_etl_project_id};
  $project_id || die "Invalid BigQuery product ID.\n";

  my $dataset_id = Bugzilla->params->{bmo_etl_dataset_id};
  $dataset_id || die "Invalid BigQuery dataset ID.\n";

  my @json_rows = ();
  foreach my $row (@{$all_rows}) {
    push @json_rows, {json => $row};
  }

  my $big_query = {
    resource   => 'tabledata',
    method     => 'insertAll',
    project_id => $project_id,
    dataset_id => $dataset_id,
    table_id   => $table,
    content    => {rows => \@json_rows}
  };

  if ($test) {
    my $filename
      = bz_locations()->{'datadir'} . '/'
      . $file_snapshot . '_'
      . $table . '_'
      . $current_count . '.json';

    print "Writing data to $filename\n" if $verbose;

    my $fh = path($filename)->open('>>');
    print $fh encode_json($big_query) . "\n";
    close $fh || die "Could not close $filename: $!\n";

    return;
  }

  my $base_url = Bugzilla->params->{bmo_etl_base_url};
  $base_url || die "Invalid BigQuery base URL.\n";

  my $http_headers = HTTP::Headers->new;

  # Do not attempt to get access token if running in test environment
  #if ($base_url !~ |http://bigquery|) {
    my $access_token = _get_access_token();
    $http_headers->header(Authorization => 'Bearer ' . $access_token);
  #}

  my $full_path = sprintf 'projects/%s/datasets/%s/tables/%s/insertAll',
    $project_id, $dataset_id, $table;

  print "Sending to $base_url/$full_path\n" if $verbose;

  my $request = HTTP::Request->new('POST', "$base_url/$full_path", $http_headers);
  $request->header('Content-Type' => 'application/json');
  $request->content(encode_json($big_query));

  my $res = $ua->request($request);
  if (!$res->is_success) {
    die 'Google Big Query insert failure: ' . $res->content;
  }
}

sub _get_access_token {
  state $access_token;    # We should only need to get this once

  return $access_token if defined $access_token;

# Google Kubernetes allows for the use of Workload Identity. This allows
# us to link two serice accounts together and give special access for applications
# running under Kubernetes. We use the special access to get an OAuth2 access_token
# that can then be used for accessing the the Google API such as BigQuery.
  my $url
    = sprintf
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/%s/token',
    Bugzilla->params->{bmo_etl_service_account};

  my $http_headers = HTTP::Headers->new;
  $http_headers->header('Metadata-Flavor' => 'Google');

  my $request = HTTP::Request->new('GET', $url, $http_headers);

  my $res = $ua->request($request);

  if (!$res->is_success) {
    die 'Google access token failure: ' . $res->content;
  }

  my $result = decode_json($res->decoded_content);
  $access_token = $result->{access_token};

  return $access_token;
}

1;
