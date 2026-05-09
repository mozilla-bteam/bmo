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

# Pulsebot needs to be able to make the following API calls as part
# of its normal workflow
# 1. GET /rest/bug/{bugid}?include_fields=keywords,status,whiteboard
# 2. GET /rest/bug/{bugid}/comment?include_fields=text
# 3. POST /rest/bug/{bugid}/comment
# 	 {"comment":"Some comment"}
# 4. PUT /rest/bug/{bugid}
# 	 {
# 		 "keywords": {
# 		  	"remove": ["checkin-needed","checkin-needed-tb"]
# 		 },
# 		 "status":"RESOLVED",
# 		 "resolution": "FIXED",
# 		 "comment": {
# 		  	"body": "Some comment"
# 		 }
# 	}

my $config           = get_config();
my $admin_api_key    = $config->{admin_user_api_key};
my $pulsebot_api_key = $config->{pulsebot_user_api_key};
my $url              = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Create a public bug for testing pulsebot functionality
my $public_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test Pulsebot Uplift',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a public test bug',
  keywords    => ['checkin-needed-tb'],
  whiteboard  => 'checkin-needed',
};

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json =>
    $public_bug)->status_is(200)->json_has('/id');

my $public_bug_id = $t->tx->res->json->{id};

# Make sure pulsebot user can see the public bug through the normal API
$t->get_ok(
  $url . "rest/bug/$public_bug_id" => {'X-Bugzilla-API-Key' => $pulsebot_api_key})
  ->status_is(200)->json_is('/bugs/0/id', $public_bug_id);

# As well through the custom API
$t->get_ok($url
    . "rest/pulsebot/bug/$public_bug_id" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(200)
  ->json_is('/bugs/0/id', $public_bug_id);

# Create a new private test bug for testing pulsebot access.
# The bug should not be visible to the pulsebot user.
my $private_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test Pulsebot Uplift',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a private test bug',
  groups      => ['Master'],
  keywords    => ['checkin-needed-tb'],
  whiteboard  => 'checkin-needed',
};

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json =>
    $private_bug)->status_is(200)->json_has('/id');

my $private_bug_id = $t->tx->res->json->{id};

# Make sure pulsebot user cannot see the private bug through the normal API
$t->get_ok($url
    . "rest/bug/$private_bug_id" => {'X-Bugzilla-API-Key' => $pulsebot_api_key})
  ->status_is(401);

# But pulsebot should be able to see the bug via the custom API
# Also make sure the pulsebot user can only see a limited amount of the bug data
$t->get_ok($url
    . "rest/pulsebot/bug/$private_bug_id" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(200)
  ->json_is('/bugs/0/id',         $private_bug_id)
  ->json_is('/bugs/0/whiteboard', $private_bug->{whiteboard})
  ->json_is('/bugs/0/keywords/0', 'checkin-needed-tb')
  ->json_is('/bugs/0/status',     'CONFIRMED')->json_hasnt('/bugs/0/milestone');

# As pulsebot user, update the bug by clearing checkin needed text from whiteboard and
# and set the status. This should work even if pulsebot cannot see the bug.

# First try with too many parameters. Should fail.
my $update = {
  ids        => [$private_bug_id],
  status     => 'RESOLVED',
  resolution => 'FIXED',
  platform   => 'All',
  comment    => {
    body => "Pushed by dwillcoxon\@mozilla.com:\n
https://hg.mozilla.org/integration/autoland/rev/04c3a110f644\n
Implement the weather suggestion result menu UI. r=dao,fluent-reviewers,flod a=dkl"
  },
  comment_tags => ['uplift']
};

$t->put_ok($url
    . 'rest/pulsebot/bug' => {'X-Bugzilla-API-Key' => $pulsebot_api_key} =>
    json                  => $update)->status_is(400)
  ->json_like('/message',
  qr/More parameters were provided that what are allowed/);

# This one should succeed since we only pass in what is allowed
delete $update->{platform};

$t->put_ok($url
    . 'rest/pulsebot/bug' => {'X-Bugzilla-API-Key' => $pulsebot_api_key} =>
    json => $update)->status_is(200)->json_is('/bugs/0/id', $private_bug_id)
  ->json_is('/bugs/0/changes/status/added',     'RESOLVED')
  ->json_is('/bugs/0/changes/resolution/added', 'FIXED');

# Retrieve the updated bug and verify that pulsebot can still see it
# Also use the query params method of specifying the bug id(s).
$t->get_ok($url
    . "rest/pulsebot/bug?id=$private_bug_id" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(200)
  ->json_is('/bugs/0/id',     $private_bug_id)
  ->json_is('/bugs/0/status', 'RESOLVED');

# Pulsebot should also be allowed to get comments from the private bug
$t->get_ok($url
    . "rest/pulsebot/bug/$private_bug_id/comment" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(200);

# Make sure the uplift tag was properly added to the latest comment
my $result   = $t->tx->res->json;
my $comments = $result->{bugs}->{$private_bug_id}->{comments};
$comments = [sort { $b->{id} <=> $a->{id} } @{$comments}];    # Sort comments newest to oldest

ok($comments->[0]->{tags}->[0] eq 'uplift', 'Uplift comment tag found');

# And comment text was added
ok($comments->[0]->{text} =~ /Pushed by dwillcoxon/,
  'Comment text added correctly');

# But comment cannot be loaded through the standard API
$t->get_ok($url
    . "rest/bug/$private_bug_id/comment" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(401);

# If pulsebot only wants to add a comment and not update anything else then
# it will call /rest/bug/{bugid}/comment. The custom API should allow it
# commenting on private bugs but not the standard API.
my $comment_data = {
  comment => "Pushed by dwillcoxon\@mozilla.com:\n
https://hg.mozilla.org/integration/autoland/rev/04c3a110f644\n
Implement the weather suggestion result menu UI. r=dao,fluent-reviewers,flod a=dkl",
  comment_tags => ['uplift']
};

$t->post_ok($url
    . "rest/bug/$private_bug_id/comment"        =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key} => json => $comment_data)
  ->status_is(401);

$t->post_ok($url
    . "rest/pulsebot/bug/$private_bug_id/comment" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key}   => json => $comment_data)
  ->status_is(200)->json_has('/id');

# Make sure the uplift tag was properly added to the latest comment
# We will need to check this using the admin user api key
$t->get_ok($url
    . "rest/pulsebot/bug/$private_bug_id/comment" =>
    {'X-Bugzilla-API-Key' => $pulsebot_api_key})->status_is(200);

$result   = $t->tx->res->json;
$comments = $result->{bugs}->{$private_bug_id}->{comments};
$comments = [sort { $b->{id} <=> $a->{id} } @{$comments}];    # Sort comments newest to oldest

ok($comments->[0]->{tags}->[0] eq 'uplift', 'Uplift comment tag found');

done_testing();
