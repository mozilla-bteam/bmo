#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This script checks for compromised accounts using the Recorded Future API
# and disables any accounts where the credentials match.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::Util qw(bz_crypt mojo_user_agent);
use Bugzilla::Mailer;

use Getopt::Long qw(:config gnu_getopt);
use LWP::UserAgent;
use JSON::MaybeXS;
use DateTime;
use Try::Tiny;
use List::Util qw(any);

use constant DISABLE_MESSAGE => <<'EOF';
Your account has been disabled because your credentials were found in a data breach.
Please contact bmo-mods@mozilla.com to reactivate your account with a new password.
EOF

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($dry_run, $help);
GetOptions('dry-run' => \$dry_run, 'help|h' => \$help,) or die <<'EOF';
usage: recorded_future.pl [--dry-run] [--token=<api_key>] [--url=<api_url>]
  --dry-run : show what would be done without actually disabling accounts
  --help|-h : show this help message
EOF

if ($help) {
  print <<'EOF';
usage: recorded_future.pl [--dry-run]

This script queries the Recorded Future API for compromised accounts related to
bugzilla.mozilla.org and disables any accounts where the email and password match.

Options:
  --dry-run : show what would be done without actually disabling accounts
  --help|-h : show this help message

The server admin will need to set the values for recorded_future_api_url and
recorded_future_api_key in the Bugzilla parameters for this script to work.

The script stores the last run timestamp in the database and uses it to fetch
only new compromised accounts since the last check.

An email report is sent to the maintainer address configured in Bugzilla
listing all accounts that were disabled.
EOF
  exit 0;
}

# Get API credentials from command line or environment
my $params  = Bugzilla->params;
my $api_key = $params->{recorded_future_api_key};
my $api_url = $params->{recorded_future_api_uri};

die 'ERROR: Recorded Future API key is required.' unless $api_key;
die 'ERROR: Recorded Future API URL is required.' unless $api_url;

Bugzilla->set_user(Bugzilla::User->check({name => 'automation@bmo.tld'}));

my $dbh = Bugzilla->dbh;

say 'Checking for compromised accounts via Recorded Future API...';

# Get the last run timestamp from the database
my $last_run_ts = $dbh->selectrow_array(
  'SELECT value FROM recorded_future WHERE name = \'last_run_ts\'');

# Build query parameters for the API
# API expects YYYY-MM-DD format and uses latest_downloaded_gte parameter
my @query_params;
push @query_params, 'domain=bugzilla.mozilla.org';

if ($last_run_ts) {
  say "Last check was at: $last_run_ts";

  # Convert timestamp to YYYY-MM-DD format for API
  my $date_only = substr $last_run_ts, 0, 10;
  push @query_params, "latest_downloaded_gte=$date_only";
}
else {
  say 'No previous run found. Fetching all available data.';
}

# Query the Recorded Future API with pagination support
say 'Querying Recorded Future API...';
my $ua = mojo_user_agent();

my @all_identities;
my $offset          = undef;
my $page_num        = 1;
my $total_available = 0;

# Fetch all pages of results
while (1) {

  # Build query string with pagination
  my @page_params = @query_params;
  push @page_params, "offset=$offset" if $offset;
  my $query_string = @page_params ? '?' . join('&', @page_params) : '';

  my $full_url = $api_url . $query_string;
  say "Fetching page $page_num: $full_url";

  my $result
    = $ua->get($full_url =>
      {'Accept' => 'application/json', 'Authorization' => "Bearer $api_key"})
    ->result;

  if (!$result->is_success) {
    die "ERROR: Recorded Future API returned error:\n"
      . ($result->code ? $result->code . ' - ' : '')
      . ($result->message // 'Unknown error');
  }

  # Parse the JSON response
  my $data = $result->json;

  unless ($data) {
    die 'ERROR: Failed to parse API response as JSON';
  }

  # Extract identities from response
  # API returns structure: { count: N, identities: [...], next_offset: "..." }
  my $identities = $data->{identities} // [];

  unless (ref $identities eq 'ARRAY') {
    die
      'ERROR: Unexpected API response format. Expected "identities" array but got: '
      . ref $data;
  }

  $total_available = $data->{count} // 0;
  my $page_count = scalar @{$identities};

  say "Page $page_num: Fetched $page_count identities";

  # Accumulate identities from this page
  push @all_identities, @{$identities};

  # Check if there are more pages
  my $next_offset = $data->{next_offset};
  if ($next_offset) {
    $offset = $next_offset;
    $page_num++;

    # Small delay to avoid rate limiting (100 calls per 60 seconds = ~0.6s per call)
    # Being conservative with 1 second delay
    sleep 1;
  }
  else {
    # No more pages
    last;
  }
}

my $total_fetched = scalar @all_identities;

say
  "Fetched $total_fetched identities across $page_num page(s) (total available: $total_available)";

if ($total_fetched == 0) {
  say 'No new compromised accounts found.';

  # Update the last run timestamp even if no accounts found
  update_last_run() unless $dry_run;
  exit 0;
}

# Process each identity and their credentials
# Each identity contains: { identity: { subjects: [...] }, credentials: [...], count: N }
my $total_credentials = 0;
my $matched_count     = 0;
my $disabled_count    = 0;
my @disabled_users;

foreach my $identity_data (@all_identities) {
  my $subjects    = $identity_data->{identity}{subjects} // [];
  my $credentials = $identity_data->{credentials}        // [];

  # Skip if no subjects (email addresses)
  next unless @{$subjects};

  # Get the primary email (first subject)
  my $email = $subjects->[0];

  # Check if the user exists in Bugzilla
  my $user = Bugzilla::User->new({name => $email});
  unless ($user) {
    say "User $email does not exist in system";
    next;
  }

  # Check each credential for this identity
  foreach my $credential (@{$credentials}) {
    $total_credentials++;

    # Extract password from exposed_secret
    # Structure: { exposed_secret: { clear_text_value: "password", ... } }
    my $exposed_secret = $credential->{exposed_secret} // {};
    my $password       = $exposed_secret->{clear_text_value};

    # Skip if no cleartext password
    unless ($password) {
      say "User $email password not found";
      next;
    }

    say "User $email password found";

    # Check if the password matches
    my $real_password_crypted    = $user->cryptpassword;
    my $entered_password_crypted = bz_crypt($password, $real_password_crypted);

    if ($entered_password_crypted eq $real_password_crypted) {
      $matched_count++;
      say "MATCH FOUND: User $email has compromised credentials!";

      # Get breach details for logging
      my $latest_downloaded = $credential->{latest_downloaded} // 'unknown';
      my $dumps             = $credential->{dumps}             // [];
      my $dump_names        = join ', ', map { $_->{name} // 'unknown' } @{$dumps};
      say "Downloaded: $latest_downloaded";
      say "Dumps: $dump_names" if $dump_names;

      if ($dry_run) {
        say "[DRY RUN] Would disable user: $email";
        push @disabled_users, $email unless any { $_ eq $email } @disabled_users;
      }
      else {
        # Check if already disabled
        if ($user->disabledtext) {
          say "User $email is already disabled. Skipping.";
          next;
        }

        # Disable the account
        try {
          $user->set_disabledtext(DISABLE_MESSAGE);
          $user->update();
          $disabled_count++;
          push @disabled_users, $email unless any { $_ eq $email } @disabled_users;
          say "User $email successfully disabled.";

          # Audit log the action
          Bugzilla->audit(
            sprintf
              'Disabled account %s due to compromised credentials found in data breach',
            $user->login
          );
        }
        catch {
          warn "ERROR: Failed to disable user $email: $_";
        };
      }

      # Once we find a matching password, no need to check other credentials for this user
      last;
    }
  }
}

say
  "Summary:\nTotal identities fetched: $total_fetched (from $page_num page(s))\n"
  . "Total credentials checked: $total_credentials\n"
  . "Accounts found in Bugzilla with matching passwords: $matched_count";

if ($dry_run) {
  say "[DRY RUN] Accounts that would be disabled: $matched_count";
}
else {
  say "Accounts successfully disabled: $disabled_count";

  # Update the last run timestamp
  update_last_run();
}

# Send email notification if accounts were disabled
if (@disabled_users) {
  my $maintainer = Bugzilla->params->{maintainer};
  my $urlbase    = Bugzilla->params->{urlbase};

  my $subject = sprintf '[BMO] %d compromised account%s disabled',
    scalar(@disabled_users), scalar(@disabled_users) == 1 ? '' : 's';

  my $body = 'The following Bugzilla accounts were ';
  $body
    .= $dry_run
    ? "identified as compromised (DRY RUN):\n\n"
    : "disabled due to compromised credentials:\n\n";

  foreach my $email (sort @disabled_users) {
    $body .= "  - $email\n";
  }

  $body .= "\n";
  $body .= 'Total: ' . scalar(@disabled_users) . ' account';
  $body .= scalar(@disabled_users) == 1 ? "\n\n" : "s\n\n";
  $body .= "These credentials were found in a data breach via Recorded Future.\n";
  $body
    .= 'The accounts '
    . ($dry_run ? 'would have been' : 'have been')
    . " disabled and the users will need to contact\n";
  $body .= "bmo-mods\@mozilla.com to reactivate with a new password.\n\n";
  $body .= "Script: recorded_future.pl\n";
  $body .= 'Run time: ' . DateTime->now->strftime('%Y-%m-%d %H:%M:%S %Z') . "\n";
  $body .= 'Last check: ' . ($last_run_ts // 'Never') . "\n";

  say "Sending notification email to: $maintainer";

  try {
    my $email = Email::MIME->create(
      header_str => [From => $maintainer, To => $maintainer, Subject => $subject,],
      attributes => {
        content_type => 'text/plain',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable',
      },
      body_str => $body,
    );

    MessageToMTA($email);
    say 'Notification email sent successfully.';
  }
  catch {
    warn "ERROR: Failed to send notification email: $_";
  };
}

say 'Done.';

sub update_last_run {
  my $current_ts = DateTime->now->strftime('%Y-%m-%d %H:%M:%S');
  $dbh->do(
    'INSERT INTO recorded_future (name, value) VALUES (?, ?) '
      . 'ON DUPLICATE KEY UPDATE value = ?',
    undef, 'last_run_ts', $current_ts, $current_ts
  );
  say "Updated last run timestamp to: $current_ts";
}
