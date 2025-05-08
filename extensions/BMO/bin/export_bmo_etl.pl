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
use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Flag;
use Bugzilla::Group;
use Bugzilla::Logging;
use Bugzilla::User;
use Bugzilla::Extension::Review::FlagStateActivity;

use HTTP::Headers;
use HTTP::Request;
use IO::Compress::Gzip     qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use List::Util             qw(any);
use LWP::UserAgent::Determined;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json false true);
use Mojo::Util qw(getopt);
use Try::Tiny;

# BigQuery API cannot handle payloads larger than 10MB so
# we will send data in blocks.
use constant API_BLOCK_COUNT => 1000;

# Products which we should not send data to ETL such as Legal, etc.
use constant EXCLUDE_PRODUCTS => ('Legal',);

# Log levels
use constant DEBUG_OUTPUT => 1;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
getopt
  't|test'            => \my $test,
  'q|quiet'           => \my $quiet,
  'd|debug'           => \my $debug,
  's|snapshot-date=s' => \my $snapshot_date,
  'n|no-cache=s'      => \my @no_cache;

# Create a hash for faster checking later
my %no_cache = map { $_ => 1 } @no_cache;

# Sanity checks
Bugzilla->params->{bmo_etl_enabled} || die "BMO ETL not enabled.\n";

my $base_url = Bugzilla->params->{bmo_etl_base_url};
$base_url || die "Invalid BigQuery base URL.\n";

my $project_id = Bugzilla->params->{bmo_etl_project_id};
$project_id || die "Invalid BigQuery product ID.\n";

my $dataset_id = Bugzilla->params->{bmo_etl_dataset_id};
$dataset_id || die "Invalid BigQuery dataset ID.\n";

# Check to make sure another instance is not currently running
check_and_set_lock();

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
if (!$snapshot_date) {
  $snapshot_date = $dbh->selectrow_array(
    'SELECT ' . $dbh->sql_date_format('LOCALTIMESTAMP(0)', '%Y-%m-%d'));
}

# Excluded bugs: List of bug ids that we should not send data for to ETL (i.e. Legal, etc.)
our %excluded_bugs = ();

# Bugs that are private to one or more groups
our %private_bugs = ();

# In order to avoid entering duplicate data, we will first query BigQuery
# to make sure other entries with this date are not already present.
check_for_duplicates();

# Process each table to be sent to ETL
process_bugs();
process_attachments();
process_flags();
process_flag_state_activity();
process_tracking_flags();
process_keywords();
process_see_also();
process_users();

process_two_columns(
  'bug_mentors', 'bug_mentors',
  ['bug_id', 'user_id'],
  ['bug_id', 'user_id']
);
process_two_columns(
  'dependencies', 'bug_dependencies',
  ['blocked', 'dependson'],
  ['bug_id',  'depends_on_id']
);
process_two_columns(
  'regressions', 'bug_regressions',
  ['regresses', 'regressed_by'],
  ['bug_id',    'regresses_id']
);
process_two_columns(
  'duplicates', 'bug_duplicates',
  ['dupe',   'dupe_of'],
  ['bug_id', 'duplicate_of_id']
);

# If we are done, remove the lock
delete_lock();

### Functions

sub process_bugs {
  my $table_name  = 'bugs';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM bugs');
  logger("Processing $total $table_name");

  my $sth
    = $dbh->prepare(
    'SELECT bug_id AS id, delta_ts AS modification_time FROM bugs ORDER BY bug_id LIMIT ? OFFSET ?'
    );

  while ($count < $total) {
    my @bugs = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $mod_time) = $sth->fetchrow_array()) {
      logger("Processing id $id with mod_time of $mod_time.");

      # First check to see if we have a cached version with the same modification date
      my $data = get_cache($id, $table_name, $mod_time);

      if (!$data) {
        logger("$table_name id $id with time $mod_time not found in cache.", DEBUG_OUTPUT);

        my $obj = Bugzilla::Bug->new($id);

        my $bug_is_private = scalar @{$obj->groups_in};

        if (any { $obj->product eq $_ } EXCLUDE_PRODUCTS) {
          $excluded_bugs{$obj->id} = 1;
          $count++;
          next;
        }

        $private_bugs{$obj->id} = 1 if $bug_is_private;

        # Standard non-sensitive fields
        $data = {
          id             => $obj->id,
          status         => $obj->bug_status,
          type           => $obj->bug_type,
          component      => $obj->component,
          creation_ts    => $obj->creation_ts,
          updated_ts     => $obj->delta_ts,
          op_sys         => $obj->op_sys,
          product        => $obj->product,
          platform       => $obj->rep_platform,
          reporter_id    => $obj->reporter->id,
          version        => $obj->version,
          team_name      => $obj->component_obj->team_name,
          classification => $obj->classification,
          comment_count  => $obj->comment_count,
          vote_count     => $obj->votes,
        };

        # Fields that require custom values based on criteria
        $data->{assignee_id}
          = $obj->assigned_to->login ne 'nobody@mozilla.org'
          ? $obj->assigned_to->id
          : undef;
        $data->{url}
          = (!$bug_is_private && $obj->bug_file_loc) ? $obj->bug_file_loc : undef;
        $data->{severity} = $obj->bug_severity ne '--' ? $obj->bug_severity : undef;
        $data->{crash_signature}
          = (!$bug_is_private && $obj->cf_crash_signature)
          ? $obj->cf_crash_signature
          : undef;
        $data->{priority}   = $obj->priority ne '--' ? $obj->priority   : undef;
        $data->{resolution} = $obj->resolution       ? $obj->resolution : undef;
        $data->{summary}    = !$bug_is_private       ? $obj->short_desc : undef;
        $data->{whiteboard}
          = (!$bug_is_private && $obj->status_whiteboard)
          ? $obj->status_whiteboard
          : undef;
        $data->{milestone}
          = $obj->target_milestone ne '---' ? $obj->target_milestone : undef;
        $data->{is_public} = $bug_is_private ? true : false;
        $data->{cc_count}  = scalar @{$obj->cc || []};

        # If more than one group, then pick the one with the least of amount of members
        if (!$bug_is_private) {
          $data->{group} = undef;
        }
        elsif (scalar @{$obj->groups_in} == 1) {
          my $groups = $obj->groups_in;
          $data->{group} = $groups->[0]->name;
        }
        else {
          $data->{group} = get_multi_group_value($obj);
        }

        # Store a copy of the data for use in later executions
        store_cache($obj->id, $table_name, $obj->delta_ts, $data);
      }

      push @bugs, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@bugs, $count) if @bugs;
  }
}

sub process_attachments {
  my $table_name  = 'attachments';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM attachments');
  logger("Processing $total $table_name.");

  my $sth
    = $dbh->prepare(
    'SELECT attach_id, modification_time FROM attachments ORDER BY attach_id LIMIT ? OFFSET ?'
    );

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $mod_time) = $sth->fetchrow_array()) {
      logger("Processing id $id with mod_time of $mod_time.");

      # First check to see if we have a cached version with the same modification date
      my $data = get_cache($id, $table_name, $mod_time);

      if (!$data) {
        logger("$table_name id $id with time $mod_time not found in cache." , DEBUG_OUTPUT);

        my $obj = Bugzilla::Attachment->new($id);

        if ($excluded_bugs{$obj->bug_id}) {
          $count++;
          next;
        }

        # Standard non-sensitive fields
        $data = {
          id           => $obj->id,
          bug_id       => $obj->bug_id,
          creation_ts  => $obj->attached,
          content_type => $obj->contenttype,
          updated_ts   => $obj->modification_time,
          submitter_id => $obj->attacher->id,
          is_obsolete  => ($obj->isobsolete ? true : false),
        };

        # Fields that require custom values based on criteria
        my $bug_is_private = exists $private_bugs{$obj->bug_id};
        $data->{description} = !$bug_is_private ? $obj->description : undef;
        $data->{filename}    = !$bug_is_private ? $obj->filename    : undef;

        # Store a new copy of the data for use later
        store_cache($obj->id, $table_name, $obj->modification_time, $data);
      }

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@results, $count) if @results;
  }
}

sub process_flags {
  my $table_name  = 'flags';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM flags');
  logger("Processing $total $table_name.");

  my $sth = $dbh->prepare(
    'SELECT id, modification_date FROM flags ORDER BY id LIMIT ? OFFSET ?');

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $mod_time) = $sth->fetchrow_array()) {
      logger("Processing id $id with mod_time of $mod_time.");

      # First check to see if we have a cached version with the same modification date
      my $data = get_cache($id, $table_name, $mod_time);

      if (!$data) {
        logger("$table_name id $id with time $mod_time not found in cache." , DEBUG_OUTPUT);

        my $obj = Bugzilla::Flag->new($id);

        if ($excluded_bugs{$obj->bug_id}) {
          $count++;
          next;
        }

        $data = {
          id            => $obj->id,
          attachment_id => $obj->attach_id || undef,
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
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@results, $count) if @results;
  }
}

sub process_flag_state_activity {

  # Process flags that were removed today using the flag_state_activity table
  # These entries will also go into the flags table in BigQuery.
  my $table_name  = 'flag_state_activity';
  my $count       = 0;
  my $last_offset = 0;

  my $total
    = $dbh->selectrow_array(
    'SELECT COUNT(*) FROM flag_state_activity WHERE status = \'X\' AND flag_when LIKE \''
      . $snapshot_date
      . ' %\'');
  logger("Processing $total $table_name.");

  my $sth
    = $dbh->prepare(
    'SELECT id, flag_when FROM flag_state_activity WHERE status = \'X\' AND flag_when LIKE \''
      . $snapshot_date
      . ' %\' ORDER BY id LIMIT ? OFFSET ?');

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $mod_time) = $sth->fetchrow_array()) {
      logger("Processing id $id with mod_time of $mod_time.");

      # First check to see if we have a cached version with the same modification date
      my $data = get_cache($id, $table_name, $mod_time);

      if (!$data) {
        logger("$table_name id $id with time $mod_time not found in cache.", DEBUG_OUTPUT);

        my $obj = Bugzilla::Extension::Review::FlagStateActivity->new($id);

        if ($excluded_bugs{$obj->bug_id}) {
          $count++;
          next;
        }

        $data = {
          attachment_id => $obj->attachment_id || undef,
          bug_id        => $obj->bug_id,
          creation_ts   => $obj->flag_when,
          updated_ts    => $obj->flag_when,
          requestee_id  => $obj->requestee_id,
          setter_id     => $obj->setter_id,
          name          => $obj->type->name,
          value         => $obj->status,
        };

        # Store a new copy of the data for use later
        store_cache($obj->id, $table_name, $obj->flag_when, $data);
      }

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data('flags', \@results, $count) if @results;
  }
}

sub process_tracking_flags {
  my $table_name  = 'tracking_flags';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array(
    'SELECT COUNT(*)
       FROM tracking_flags_bugs
            JOIN tracking_flags
            ON tracking_flags_bugs.tracking_flag_id = tracking_flags.id
      ORDER BY tracking_flags_bugs.bug_id'
  );
  logger("Processing $total $table_name.");

  my $sth = $dbh->prepare(
    'SELECT tracking_flags_bugs.id, tracking_flags.name, tracking_flags_bugs.bug_id, tracking_flags_bugs.value
      FROM tracking_flags_bugs
           JOIN tracking_flags
           ON tracking_flags_bugs.tracking_flag_id = tracking_flags.id
      ORDER BY tracking_flags_bugs.id LIMIT ? OFFSET ?'
  );

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $name, $bug_id, $value) = $sth->fetchrow_array()) {
      if ($excluded_bugs{$bug_id}) {
        $count++;
        next;
      }

      # Standard fields
      my $data = {id => $id, bug_id => $bug_id};

      # Fields that require custom values based on other criteria
      if (exists $private_bugs{$bug_id}) {
        $data->{name}  = undef;
        $data->{value} = undef;
      }
      else {
        $data->{name}  = $name;
        $data->{value} = $value;
      }

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@results, $count) if @results;
  }
}

sub process_keywords {
  my $table_name  = 'keywords';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM keywords');
  logger("Processing $total $table_name.");

  my $sth = $dbh->prepare(
    'SELECT bug_id, keyworddefs.name
        FROM keywords
              JOIN keyworddefs
              ON keywords.keywordid = keyworddefs.id
        ORDER BY bug_id LIMIT ? OFFSET ?'
  );

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($bug_id, $keyword) = $sth->fetchrow_array()) {
      if ($excluded_bugs{$bug_id}) {
        $count++;
        next;
      }

      # Standard fields
      my $data = {bug_id => $bug_id};

      # Fields that require custom values based on other criteria
      $data->{keyword} = !exists $private_bugs{$bug_id} ? $keyword : undef;

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@results, $count) if @results;
  }
}

sub process_see_also {
  my $table_name  = 'see_also';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM bug_see_also');
  logger("Processing $total $table_name.");

  my $sth
    = $dbh->prepare(
    'SELECT bug_id, value, class FROM bug_see_also ORDER BY bug_id LIMIT ? OFFSET ?'
    );

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($bug_id, $value, $class) = $sth->fetchrow_array()) {
      if ($excluded_bugs{$bug_id}) {
        $count++;
        next;
      }

      # Standard fields
      my $data = {bug_id => $bug_id,};

      # Fields that require custom values based on other criteria
      if ($private_bugs{$bug_id}) {
        $data->{url} = undef;
      }
      elsif ($class =~ /::Local/) {
        $data->{url} = Bugzilla->localconfig->urlbase . 'show_bug.cgi?id=' . $value;
      }
      else {
        $data->{url} = $value;
      }

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@results, $count) if @results;
  }
}

sub process_users {
  my $table_name  = 'users';
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM profiles');
  logger("Processing $total $table_name.");

  my $sth
    = $dbh->prepare(
    'SELECT userid, modification_ts FROM profiles ORDER BY userid LIMIT ? OFFSET ?'
    );

  while ($count < $total) {
    my @users = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($id, $mod_time) = $sth->fetchrow_array()) {
      logger("Processing id $id with mod_time of $mod_time.");

      # Set the mod time to an arbitrary value for caching purposes if its
      # real mod time is not yet been set to a real value.
      $mod_time = '1970-01-01 12:00:00' if !$mod_time;

      # First check to see if we have a cached version with the same modification date
      my $data = get_cache($id, $table_name, $mod_time);

      if (!$data) {
        logger("$table_name id $id with time $mod_time not found in cache.", DEBUG_OUTPUT);

        my $obj = Bugzilla::User->new($id);

        # Standard fields
        $data = {
          id        => $obj->id,
          last_seen => ($obj->last_seen_date ? $obj->last_seen_date . ' 00:00:00' : undef),
          email     => $obj->email,
          is_new    => ($obj->is_new ? true : false),
        };

        # Fields that require custom values based on criteria
        $data->{nick} = $obj->nick ? $obj->nick : undef;
        $data->{name} = $obj->name ? $obj->name : undef;
        $data->{is_staff}
          = $obj->in_group('mozilla-employee-confidential') ? true : false;
        $data->{is_trusted} = $obj->in_group('editbugs') ? true             : false;
        $data->{ldap_email} = $obj->ldap_email           ? $obj->ldap_email : undef;

        # Store a new copy of the data for use later
        store_cache($obj->id, $table_name, $obj->modification_ts, $data);
      }

      push @users, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($table_name, \@users, $count) if @users;
  }
}

sub process_two_columns {
  my ($table_name, $bq_name, $column_names, $data_names) = @_;
  my $count       = 0;
  my $last_offset = 0;

  my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM ' . $table_name);
  logger("Processing $total $table_name.");

  my $columns_string = join ', ', @{$column_names};
  my $order_by       = $column_names->[0];

  my $sth = $dbh->prepare(
    "SELECT $columns_string FROM $table_name ORDER BY $order_by LIMIT ? OFFSET ?");

  while ($count < $total) {
    my @results = ();

    $sth->execute(API_BLOCK_COUNT, $last_offset);

    while (my ($value1, $value2) = $sth->fetchrow_array()) {
      if ($excluded_bugs{$value1}) {
        $count++;
        next;
      }

      logger("Processing values $value1, $value2 for $table_name.");

      my $data = {$data_names->[0] => $value1, $data_names->[1] => $value2,};

      push @results, $data;

      $count++;
    }

    $last_offset += API_BLOCK_COUNT;

    # Send the rows to the server
    send_data($bq_name, \@results, $count) if @results;
  }
}

sub get_cache {
  my ($id, $table, $timestamp) = @_;

  if ($no_cache{$table}) {
    logger("Retrieving cached data is disabled for $table.");
    return undef;
  }

  logger("Retreiving data from $table for $id with time $timestamp.", DEBUG_OUTPUT);

  try {
  # Retrieve compressed JSON from cache table if it exists
  my $gzipped_data = $dbh->selectrow_array(
    'SELECT data FROM bmo_etl_cache WHERE id = ? AND table_name = ? AND snapshot_date = ?',
    undef, $id, $table, $timestamp
  );
  return undef if !$gzipped_data;

  # First uncompress the JSON and then decode it back to Perl data
  my $data;
  unless (gunzip \$gzipped_data => \$data) {
    delete_lock();
    die "gunzip failed: $GunzipError\n";
  }
  return decode_json($data);
  }
  catch {
    # Log the failure and return undef
    WARN("ERROR: Unable to retrieve cached data from database: $_");
    return undef;
  }
}

sub store_cache {
  my ($id, $table, $timestamp, $data) = @_;

  if ($no_cache{$table}) {
    logger("Storing cached data is disabled for $table.");
    return undef;
  }

  logger("Storing data into $table for $id with time $timestamp.", DEBUG_OUTPUT);

  # Encode the perl data into JSON
  $data = encode_json($data);

  # Compress the JSON to save space in the DB
  my $gzipped_data;
  unless (gzip \$data => \$gzipped_data) {
    delete_lock();
    die "gzip failed: $GzipError\n";
  }

  # We need to use the main DB for write operations
  my $main_dbh = Bugzilla->dbh_main;

  try {
    # Clean out outdated JSON
    $main_dbh->do('DELETE FROM bmo_etl_cache WHERE id = ? AND table_name = ?',
      undef, $id, $table);

    # Enter new cached JSON
    $main_dbh->do(
      'INSERT INTO bmo_etl_cache (id, table_name, snapshot_date, data) VALUES (?, ?, ?, ?)',
      undef, $id, $table, $timestamp, $gzipped_data
    );
  }
  catch {
    # Log the failure
    WARN("ERROR: Unable to store cache data in database: $_");
  }
}

sub send_data {
  my ($table, $all_rows, $current_count) = @_;

  logger('Sending ' . scalar @{$all_rows} . " rows to table $table using BigQuery API");

  # Add the same snapshot date to every row sent
  foreach my $row (@{$all_rows}) {
    $row->{snapshot_date} = $snapshot_date;
  }

  my @json_rows = ();
  foreach my $row (@{$all_rows}) {
    push @json_rows, {json => $row};
  }

  my $big_query = {rows => \@json_rows};

  if ($test) {
    my $filename
      = bz_locations()->{'datadir'} . '/'
      . $snapshot_date . '-'
      . $table . '-'
      . $current_count . '.json';

    logger("Writing data to $filename.");

    my $fh = path($filename)->open('>>');
    print $fh encode_json($big_query) . "\n";
    unless (close $fh) {
      delete_lock();
      die "Could not close $filename: $!\n";
    }

    return;
  }

  my $http_headers = HTTP::Headers->new;

  # Do not attempt to get access token if running in test environment
  if ($base_url !~ /^http:\/\/[^\/]+:9050/) {
    my $access_token = _get_access_token();
    $http_headers->header(Authorization => 'Bearer ' . $access_token);
  }

  my $full_path = sprintf 'projects/%s/datasets/%s/tables/%s/insertAll',
    $project_id, $dataset_id, $table;

  logger("Sending to $base_url/$full_path", DEBUG_OUTPUT);

  my $request = HTTP::Request->new('POST', "$base_url/$full_path", $http_headers);
  $request->header('Content-Type' => 'application/json');

  logger('Encoding content into JSON.', DEBUG_OUTPUT);

  $request->content(encode_json($big_query));

  logger('Sending request', DEBUG_OUTPUT);

  my $response = $ua->request($request);

  logger($response->content, DEBUG_OUTPUT);

  my $result = decode_json($response->content);

  if (!$response->is_success
    || (exists $result->{insertErrors} && @{$result->{insertErrors}}))
  {
    delete_lock();
    die "Google Big Query insert failure:\nRequest:\n"
      . $request->content
      . "\n\nResponse:\n"
      . $response->content . "\n";
  }
}

sub _get_access_token {
  state $access_token;    # We should only need to get this once
  state $token_expiry;

  logger('Checking for acess token', DEBUG_OUTPUT);

  # If we already have a token and it has not expired yet, just return it
  if ($access_token && time < $token_expiry) {
    logger('Previous access token found', DEBUG_OUTPUT);
    return $access_token;
  }

  # Google Kubernetes allows for the use of Workload Identity. This allows
  # us to link two service accounts together and give special access for applications
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
    delete_lock();
    die 'Google access token failure: ' . $res->content . "\n";
  }

  my $result = decode_json($res->decoded_content);
  $access_token = $result->{access_token};
  $token_expiry = time + $result->{expires_in};

  logger('New access token returned', DEBUG_OUTPUT);

  return $access_token;
}

# If a previous process is performing an export to BigQuery, then
# we must check the lock table and exit if true.
sub check_and_set_lock {
  return if $test;    # No need if just dumping test files

  logger('Checking for previous lock or setting new one', DEBUG_OUTPUT);

  my $dbh_main = Bugzilla->dbh_main;

  # Clear out any locks that are greater than 24h old
  $dbh_main->do('DELETE FROM bmo_etl_locked WHERE creation_ts < '
      . $dbh_main->sql_date_math('NOW()', '-', 24, 'HOUR'));

  # Now check for any pre-existing locks and do not proceed if one found
  my $locked = $dbh_main->selectrow_array('SELECT COUNT(*) FROM bmo_etl_locked');
  if ($locked) {
    die "Another process has set a lock. Exiting\n";
  }

  logger('Previous lock not found. Setting new one.', DEBUG_OUTPUT);

  $dbh_main->do('INSERT INTO bmo_etl_locked (value, creation_ts) VALUES (?, NOW())', undef, 'locked');
}

# Delete lock from bmo_etl_locked
sub delete_lock {
  logger("Deleting lock in database.");
  Bugzilla->dbh_main->do('DELETE FROM bmo_etl_locked');
}

sub check_for_duplicates {
  return if $test;    # no need if just dumping test files

  logger("Checking for duplicate data for snapshot date $snapshot_date.");

  my $http_headers = HTTP::Headers->new;

  # Do not attempt to get access token if running in test environment
  if ($base_url !~ /^http:\/\/[^\/]+:9050/) {
    my $access_token = _get_access_token();
    $http_headers->header(Authorization => 'Bearer ' . $access_token);
  }

  my $full_path = "projects/$project_id/queries";

  logger("Querying $base_url/$full_path", DEBUG_OUTPUT);

  my $query = {
    query =>
      "SELECT count(*) FROM ${project_id}.${dataset_id}.bugs WHERE snapshot_date = '$snapshot_date';",
    useLegacySql => false,
  };

  my $request = HTTP::Request->new('POST', "$base_url/$full_path", $http_headers);
  $request->header('Content-Type' => 'application/json');
  $request->content(encode_json($query));

  logger(encode_json($query), DEBUG_OUTPUT);

  my $res = $ua->request($request);
  if (!$res->is_success) {
    delete_lock();
    die 'Google Big Query query failure: ' . $res->content . "\n";
  }

  logger($res->content, DEBUG_OUTPUT);

  my $result = decode_json($res->content);

  my $row_count = $result->{rows}->[0]->{f}->[0]->{v};

  # Do not export if we have any rows with this snapshot date.
  if ($row_count) {
    delete_lock();
    die "Duplicate data found for snapshot date $snapshot_date\n";
  }
}

sub get_multi_group_value {
  my ($bug) = @_;

  logger('Checking for multi group values.', DEBUG_OUTPUT);

  my $smallest_group_name  = undef;
  my $smallest_group_count = 0;

  foreach my $group (@{$bug->groups_in}) {
    my $user_count  = 0;
    my $member_data = $group->members_complete;
    foreach my $type (keys %{$member_data}) {
      $user_count += scalar @{$member_data->{$type}};
    }
    if ($user_count < $smallest_group_count) {
      $smallest_group_count = $user_count;
      $smallest_group_name  = $group->name;
    }
  }

  logger("Smallest group members: $smallest_group_name") if $smallest_group_name;

  return $smallest_group_name;
}

sub logger {
  my ($message, $level) = @_;

  # Skip if -q or --quiet was specified
  return if $quiet;

  # Skip if --debug was not specified and this is a DEBUG level entry
  return if (defined $level && $level == DEBUG_OUTPUT && !$debug);

  # Otherwise just print
  print time() . ": $message\n";
}

1;
