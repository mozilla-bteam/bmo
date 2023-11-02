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
use QA::Util  qw(get_config);
use QA::Tests qw(create_bug_fields PRIVATE_BUG_USER);

use Mojo::Util qw(dumper);
use Test::Mojo;
use Test::More;
use Sys::Hostname;

my $config                = get_config();
my $editbugs_user_api_key = $config->{editbugs_user_api_key};
my $url                   = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Create first bug

my $bug_data = create_bug_fields($config);
$bug_data->{summary}     = 'This is a public test bug';
$bug_data->{description} = 'This is a public test bug';

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $bug1_id = $t->tx->res->json->{id};

### Section 2: Create second bug that depends on the first bug

$bug_data->{depends_on} = [$bug1_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $bug2_id = $t->tx->res->json->{id};

### Section 3: Create a third bug that depends on the second bug

$bug_data->{depends_on} = [$bug2_id];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $editbugs_user_api_key} => json =>
    $bug_data)->status_is(200)->json_has('/id');

my $bug3_id = $t->tx->res->json->{id};

### Section 4: Load the dependency graph

$t->get_ok($url
    . "rest/bug/${bug1_id}/graph?type=bug_tree&relationship=dependencies:dependson,blocked"
    => {'X-Bugzilla-API-Key' => $editbugs_user_api_key})->status_is(200)
  ->json_is('/tree/5/6/bug/summary', 'This is a public test bug');

done_testing();
