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
use QA::Util qw(get_config);

use Test::Mojo;
use Test::More;

my $config        = get_config();
my $admin_api_key = $config->{'admin_user_api_key'};
my $lando_api_key = $config->{lando_user_api_key};
my $url           = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Create a new private test bug for testing Lando uplift
# The bug should not be visible to the Lando user.
my $new_bug = {
  product           => 'Firefox',
  component         => 'General',
  summary           => 'Test Lando Uplift',
  type              => 'defect',
  version           => 'unspecified',
  severity          => 'blocker',
  description       => 'This is a new test bug',
  groups            => ['Master'],
  status_whiteboard => '[checkin-needed-mozilla-central]',
};

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $admin_api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# Make sure Lando user cannot see bug through the normal API
$t->get_ok(
  $url . "rest/bug/$bug_id" => {'X-Bugzilla-API-Key' => $lando_api_key})
  ->status_is(401);

# Make sure the Lando user can see a limit amount of bug data through the custom endpoint
$t->get_ok(
  $url . "rest/lando/uplift/$bug_id" => {'X-Bugzilla-API-Key' => $lando_api_key})
  ->status_is(200)->json_is('/bugs/0/id', $bug_id)
  ->json_is('/bugs/0/whiteboard',           $new_bug->{status_whiteboard})
  ->json_is('/bugs/0/cf_status_firefox111', '---');

# As Lando user, update the bug and clear checkin needed text from whiteboard and set the
# status-firefox111 flag. This should work even if Lando cannot see the bug.
my $update
  = {ids => [$bug_id], 'whiteboard' => '', 'cf_status_firefox111' => 'fixed'};
$t->put_ok($url
    . 'rest/lando/uplift' => {'X-Bugzilla-API-Key' => $lando_api_key} => json =>
    $update)->status_is(200)->json_is('/bugs/0/id', $bug_id)
  ->json_is('/bugs/0/changes/cf_status_firefox111/added', 'fixed')
  ->json_is('/bugs/0/changes/whiteboard/added',           '');

$t->get_ok(
  $url . "rest/lando/uplift/$bug_id" => {'X-Bugzilla-API-Key' => $lando_api_key})
  ->status_is(200)->json_is('/bugs/0/id', $bug_id)
  ->json_is('/bugs/0/whiteboard',           '')
  ->json_is('/bugs/0/cf_status_firefox111', 'fixed');

done_testing();
