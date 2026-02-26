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

use Mojo::JSON qw(true);
use Mojo::Util qw(dumper);
use Test::Mojo;
use Test::More;

my $config               = get_config();
my $admin_api_key        = $config->{admin_user_api_key};
my $unprivileged_api_key = $config->{unprivileged_user_api_key};
my $unprivileged_login   = $config->{unprivileged_user_login};
my $url                  = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Create a new group for testing
my $new_group = {
  name        => 'secret-group',
  description => 'Too secret for you!',
  is_active   => true
};
$t->post_ok($url
    . 'rest/group' => {'X-Bugzilla-API-Key' => $admin_api_key} => json =>
    $new_group)->status_is(201)->json_has('/id');

my $group_id = $t->tx->res->json->{id};

# Make sure we can get the group details back
$t->get_ok(
  $url . "rest/group/$group_id" => {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200)->json_is('/groups/0/name', 'secret-group');

# Create a new user and add it to the new group
my $new_user = {
  email     => 'group_test_user@mozilla.bugs',
  full_name => 'Group Test User',
  password  => 'password123456789!'
};
$t->post_ok($url
    . 'rest/user' => {'X-Bugzilla-API-Key' => $admin_api_key} => json =>
    $new_user)->status_is(201)->json_has('/id');

my $user_id = $t->tx->res->json->{id};

my $user_update = {groups => {add => ['secret-group']}};
$t->put_ok(
  $url . "rest/user/$user_id" => {'X-Bugzilla-API-Key' => $admin_api_key} => json => $user_update)
  ->status_is(200)->json_has('/users');

# Observe the new user is a member of the secret-group
$t->get_ok($url
    . "rest/group/$group_id?membership=1" =>
    {'X-Bugzilla-API-Key' => $admin_api_key})->status_is(200)
  ->json_is('/groups/0/name', 'secret-group');

my $result = $t->tx->res->json;
my $user_found = 0;
foreach my $user (@{$result->{groups}->[0]->{membership}}) {
  $user_found = 1 if $user->{id} = $user_id;
}
ok($user_found, "User was included in membership list of new group");

# Unprivileged user should not be able to see group 
$t->get_ok($url . "rest/group/$group_id" => {'X-Bugzilla-API-Key' => $unprivileged_api_key})
  ->status_is(400);

# Adding the unprivileged user to the mozilla-employee-confidential
# group should allow seeing the group
$user_update = {groups => {add => ['mozilla-employee-confidential']}};
$t->put_ok(
  $url . "rest/user/$unprivileged_login" => {'X-Bugzilla-API-Key' => $admin_api_key} => json => $user_update)
  ->status_is(200)->json_has('/users');

$t->get_ok(
  $url . "rest/group/$group_id" => {'X-Bugzilla-API-Key' => $unprivileged_api_key})
  ->status_is(200)->json_is('/groups/0/name', 'secret-group');

done_testing();
