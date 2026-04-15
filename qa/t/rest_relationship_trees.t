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
use Bugzilla::QA::Util  qw(get_config);
use Bugzilla::QA::Tests qw(create_bug_fields PRIVATE_BUG_USER);

use Test::Mojo;
use Test::More;

my $config               = get_config();
my $url                  = Bugzilla->localconfig->urlbase;
my $private_user_api_key = $config->{PRIVATE_BUG_USER . '_user_api_key'};
my $unpriv_user_api_key  = $config->{unprivileged_user_api_key};

# editbugs is needed to fill in dependencies on bug entry
my $editbugs_user_api_key = $config->{editbugs_user_api_key};

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Dependencies

# Create first bug

my $bug_data = create_bug_fields($config);
delete $bug_data->{cc};    # No unprivileged user is not added to the cc list
$bug_data->{summary}     = 'This is a public test bug';
$bug_data->{description} = 'This is a public test bug';

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $depends_bug1_id = $t->tx->res->json->{id};

# Create second bug that depends on the first bug

$bug_data->{depends_on} = [$depends_bug1_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $depends_bug2_id = $t->tx->res->json->{id};

# Create a third bug that depends on the second bug

$bug_data->{depends_on} = [$depends_bug2_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $depends_bug3_id = $t->tx->res->json->{id};

# Load the dependency tree

$t->get_ok($url
    . "rest/bug/${depends_bug1_id}/graph?relationship=dependencies" =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_is("/dependson/$depends_bug2_id/$depends_bug3_id/bug/summary",
  'This is a public test bug')->json_has('/blocked');

# Only display bug ids and not load extra bug data. This could be faster
# with really large relationship trees.

$t->get_ok($url
    . "rest/bug/${depends_bug1_id}/graph?relationship=dependencies&ids_only=1" =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_has("/dependson/$depends_bug2_id/$depends_bug3_id")
  ->json_hasnt("/dependson/$depends_bug2_id/$depends_bug3_id/bug")
  ->json_has('/blocked');

# Update the bug to make private and make sure it is not visible in the tree
# by a user without proper permissions.

my $update_data = {
  summary => 'This is a private test bug',
  groups  => {add => ['QA-Selenium-TEST']}
};

$t->put_ok($url
    . "rest/bug/$depends_bug3_id"                   =>
    {'X-Bugzilla-API-Key' => $private_user_api_key} => json => $update_data)
  ->status_is(200);

# Redisplay dependency tree and verify that the private bug is missing

$t->get_ok($url
    . "rest/bug/${depends_bug1_id}/graph?relationship=dependencies" =>
    {'X-Bugzilla-API-Key' => $unpriv_user_api_key})->status_is(200)
  ->json_hasnt("/dependson/$depends_bug2_id/$depends_bug3_id");

### Section 2: Regressions

# Create first bug

$bug_data                = create_bug_fields($config);
$bug_data->{summary}     = 'This is a public test bug';
$bug_data->{description} = 'This is a public test bug';

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $regression_bug1_id = $t->tx->res->json->{id};

# Create second bug that regresses the first bug

$bug_data->{regressed_by} = [$regression_bug1_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $regression_bug2_id = $t->tx->res->json->{id};

# Create a third bug that regresses the second bug

$bug_data->{regressed_by} = [$regression_bug2_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $regression_bug3_id = $t->tx->res->json->{id};

# Load the regression tree

$t->get_ok($url
    . "rest/bug/${regression_bug1_id}/graph?relationship=regressions" =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_is("/regressed_by/$regression_bug2_id/$regression_bug3_id/bug/summary",
  'This is a public test bug')->json_has('/regresses');

# Only display bug ids and not load extra bug data. This could be faster
# with really large relationship trees.

$t->get_ok($url
    . "rest/bug/${regression_bug1_id}/graph?relationship=regressions&ids_only=1"
    => {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_has("/regressed_by/$regression_bug2_id/$regression_bug3_id")
  ->json_hasnt("/regressed_by/$regression_bug2_id/$regression_bug3_id/bug")
  ->json_has('/regresses');

### Section 2: Duplicates

# Create first bug

$bug_data                = create_bug_fields($config);
$bug_data->{summary}     = 'This is a public test bug';
$bug_data->{description} = 'This is a public test bug';

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $dupe_bug1_id = $t->tx->res->json->{id};

# Create second bug that is duplicate of the first bug

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $dupe_bug2_id = $t->tx->res->json->{id};

$update_data = {dupe_of => $dupe_bug1_id};

$t->put_ok($url
    . "rest/bug/$dupe_bug2_id"                       =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json => $update_data)
  ->status_is(200);

# Create a third bug that is duplicate of the second bug

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $dupe_bug3_id = $t->tx->res->json->{id};

$update_data = {dupe_of => $dupe_bug2_id};

$t->put_ok($url
    . "rest/bug/$dupe_bug3_id"                       =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json => $update_data)
  ->status_is(200);

# Load the regression tree

$t->get_ok($url
    . "rest/bug/${dupe_bug1_id}/graph?relationship=duplicates&show_resolved=1" =>
    {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_is("/dupe_of/$dupe_bug2_id/$dupe_bug3_id/bug/summary",
  'This is a public test bug')->json_has('/dupe');

# Only display bug ids and not load extra bug data. This could be faster
# with really large relationship trees.

$t->get_ok($url
    . "rest/bug/${dupe_bug1_id}/graph?relationship=duplicates&show_resolved=1&ids_only=1"
    => {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_has("/dupe_of/$dupe_bug2_id/$dupe_bug3_id")
  ->json_hasnt("/dupe_of/$dupe_bug2_id/$dupe_bug3_id/bug")->json_has('/dupe');

done_testing();
