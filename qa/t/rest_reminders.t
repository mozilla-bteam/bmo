#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::QA::Util qw(get_config);

use Test::Mojo;
use Test::More;

my $config  = get_config();
my $api_key = $config->{editbugs_user_api_key};
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Create a new reminder

my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'This is a new test bug',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

my $new_reminder
  = {bug_id => $bug_id, note => 'Test Reminder', reminder_ts => '2024-06-08',};

# First try unauthenticated. Should fail with error.
$t->post_ok($url . 'rest/reminder' => json => $new_reminder)->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Now try as authenticated user using API key.
$t->post_ok($url
    . 'rest/reminder' => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $new_reminder)->status_is(200)->json_is('/note' => 'Test Reminder');

my $id = $t->tx->res->json->{id};

### Section 2: View the reminder in list and single

$t->get_ok($url . 'rest/reminder' => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is('/reminders/0/note' => 'Test Reminder');

$t->get_ok($url . "rest/reminder/$id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is('/note' => 'Test Reminder');

### Section 3: Remove the reminder

$t->delete_ok($url . "rest/reminder/$id" => {'X-Bugzilla-API-Key' => $api_key})
  ->status_is(200)->json_is('/success' => 1);

done_testing();
