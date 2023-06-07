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
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::User;

use QA::Util qw(get_config);
use Test::Mojo;
use Test::More;

my $config         = get_config();
my $admin_api_key  = $config->{admin_user_api_key};
my $unpriv_api_key = $config->{unprivileged_user_api_key};
my $url            = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new;

# Example search API simply returns a list of all possible bug statuses
# or info on a single status is a status name is provided. Login is not required.
$t->get_ok($url
    . "rest/search/bug_statuses?value=NEW" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})->status_is(200)
  ->json_is('/result/0/value', 'NEW');

# The LastSeen API returns a list of bugs that have not been seen in X days by
# the assignee or have needinfo set and the requestee has not been seen in X days

# The last seen endpoints require login so we check to make sure that is enforced
$t->get_ok($url . 'rest/search/needinfo_last_seen?days=10')->status_is(401);

# Should return zero results since no user has even been around for 10 days
$t->get_ok($url
    . 'rest/search/needinfo_last_seen?days=10' =>
    {'X-Bugzilla-API-Key' => $admin_api_key})->status_is(200)
  ->json_hasnt('/result/0/id');

# Create new bug and set the admin user as assignee
my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test Bug',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
  status      => 'ASSIGNED',
  assigned_to => $config->{admin_user_login},
  groups      => ['Master'],
};

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# HACK: Do not try this at home
# Manually set the last_seen_date of the admin user to 10 days ago
Bugzilla->dbh->do(
  "UPDATE profiles SET last_seen_date = NOW() - INTERVAL 10 DAY WHERE login_name = ?",
  undef, $config->{admin_user_login}
);

# Should return the bug we just created since the admin user has not been seen in 10 days
$t->get_ok($url
    . 'rest/search/assignee_last_seen?days=5' =>
    {'X-Bugzilla-API-Key' => $admin_api_key})->status_is(200)
  ->json_is('/result/0/id', $bug_id);

# Make sure an unprivileged user cannot see the private bug
$t->get_ok($url
    . 'rest/search/assignee_last_seen?days=5' =>
    {'X-Bugzilla-API-Key' => $unpriv_api_key})->status_is(200)
  ->json_hasnt('/result/0/id');

done_testing();
