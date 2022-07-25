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

use MIME::Base64 qw(encode_base64 decode_base64);
use Test::Mojo;
use Test::More;

my $config  = get_config();
my $api_key = $config->{admin_user_api_key};
my $url     = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Create a new component

my $new_component = {
  name        => 'TestComponent',
  product     => 'Firefox',
  description => 'This is a new test component',
  team_name   => 'Mozilla',
};

# First try unauthenticated. Should fail with error.
$t->post_ok($url . 'rest/component/Firefox' => json => $new_component)
  ->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Now try as authenticated user using API key. But a required field is missing (initialowner).
$t->post_ok($url
    . 'rest/component/Firefox' => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $new_component)->status_is(400)
  ->json_is('/message' => 'A default assignee is required for this component.');

# Now try again with the missing field populated.
$new_component->{default_assignee} = 'admin@mozilla.test';
$t->post_ok($url
    . 'rest/component/Firefox' => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $new_component)->status_is(200)->json_is('/name' => 'TestComponent');

# Retrieve the new component and verify
$t->get_ok($url
    . 'rest/component/Firefox/TestComponent' =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200)
  ->json_is('/name' => 'TestComponent');

# Adding the same component should generate an error
$t->post_ok($url
    . 'rest/component/Firefox' => {'X-Bugzilla-API-Key' => $api_key} => json =>
    $new_component)->status_is(400)
  ->json_is('/message' =>
    'The Firefox product already has a component named TestComponent.');

### Section 2: Make updates to the component

my $update = {
  triage_owner     => 'admin@mozilla.test',
  description      => 'Updated description',
  default_assignee => 'permanent_user@mozilla.test'
};

# Unauthenticated update should fail
$t->put_ok($url . 'rest/component/Firefox/TestComponent' => json => $update)
  ->status_is(401)
  ->json_is(
  '/message' => 'You must log in before using this part of Bugzilla.');

# Authenticated request should work fine.
$t->put_ok($url
    . 'rest/component/Firefox/TestComponent' =>
    {'X-Bugzilla-API-Key' => $api_key}       => json => $update)->status_is(200)
  ->json_is('/triage_owner'     => 'admin@mozilla.test')
  ->json_is('/description'      => 'Updated description')
  ->json_is('/default_assignee' => 'permanent_user@mozilla.test');

# Retrieve the new component and verify
$t->get_ok($url
    . 'rest/component/Firefox/TestComponent' =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200)
  ->json_is('/triage_owner' => 'admin@mozilla.test')
  ->json_is('/description'  => 'Updated description');

done_testing();
