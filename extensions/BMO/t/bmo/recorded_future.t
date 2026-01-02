#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5 qa/t/lib);

use Bugzilla;
use Bugzilla::User;
use Bugzilla::Test::Util qw(create_user);

BEGIN { Bugzilla->extensions }

use QA::Util;
use Test::More;
use Test::Mojo;
use Capture::Tiny qw(capture);

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Reports' => {
      'recorded_future_api_uri' => {
        type  => 'text',
        value => 'http://externalapi.test:8001'
      },
      'recorded_future_api_key' => {type => 'text', value => 'test_api_key'},
    }
  }
);

# Create test users with known passwords
# test1@example.com with password "correctpassword123!" (will match breach)
# test2@example.com with password "wrongpassword123!" (won't match)
create_user('test1@example.com', 'correctpassword123!',
  realname => 'Test User 1');
create_user('test2@example.com', 'wrongpassword123!',
  realname => 'Test User 2');
create_user('test3@example.com', 'wrongpassword123!',
  realname => 'Test User 3');

# Run the recorded_future.pl script in dry-run mode
my @cmd
  = ('perl', 'extensions/BMO/bin/recorded_future.pl', '--dry-run', '--domain', 'example.com', '2>&1');
my ($output, $error, $exit_code) = capture { system @cmd; };

# Check that the script ran successfully
is($exit_code, 0, 'Script executed without errors');

# Verify output contains expected messages
like($output, qr/Querying Recorded Future API/, 'Script queried the API');
like($output, qr/Fetching page \d+/, 'Script fetched at least one page');
like(
  $output,
  qr/Fetched \d+ identities across \d+ page/,
  'Script processed identities'
);

# Check for pagination handling
like($output, qr/Page 1: Fetched \d+ identities/, 'Script fetched page 1');
like(
  $output,
  qr/Page 2: Fetched \d+ identities/,
  'Script fetched page 2 (pagination working)'
);

# Verify that test1@example.com was identified (password matches)
like(
  $output,
  qr/MATCH FOUND: User test1\@example\.com/,
  'Found matching password for test1@example.com'
);

# Verify dry-run message
like(
  $output,
  qr/\[DRY RUN\] Would disable user: test1\@example\.com/,
  'Dry run mode prevented actual account disabling'
);

# Verify that test2@example.com was NOT identified (password doesn't match)
unlike(
  $output,
  qr/MATCH FOUND: User test2\@example\.com/,
  'Did not match test2@example.com (different password)'
);

# Verify summary output
like($output, qr/Total identities fetched: 3/, 'Fetched 3 identities total');
like(
  $output,
  qr/Accounts found in Bugzilla with matching passwords: 1/,
  'Found 1 account with matching password'
);

# Now run without dry-run to test actual disabling
@cmd = ('perl', 'extensions/BMO/bin/recorded_future.pl', '--domain', 'example.com', '2>&1');
($output, $error, $exit_code) = capture { system @cmd; };

is($exit_code, 0, 'Script executed without errors (non-dry-run)');

# Verify that test1 was actually disabled
my $test1_user = Bugzilla::User->new({name => 'test1@example.com'});
ok($test1_user->disabledtext, 'test1@example.com was disabled');
like(
  $test1_user->disabledtext,
  qr/credentials were found in a data breach/,
  'Disabled message mentions data breach'
);

# Verify that test2 was NOT disabled
my $test2_user = Bugzilla::User->new({name => 'test2@example.com'});
ok(!$test2_user->disabledtext, 'test2@example.com was not disabled');

# Test incremental updates: run again and verify no new matches
@cmd = ('perl', 'extensions/BMO/bin/recorded_future.pl', '--domain', 'example.com', '2>&1');
($output, $error, $exit_code) = capture { system @cmd; };

is($exit_code, 0, 'Script ran successfully on second run');
like($output, qr/Last check was at:/, 'Script used last run timestamp');

set_parameters($sel,
  {'Reports' => {'recorded_future_api_uri' => {type => 'text', value => ''}}});
logout($sel);

done_testing();
