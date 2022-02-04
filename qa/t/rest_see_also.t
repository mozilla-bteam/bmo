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
use QA::Tests qw(create_bug_fields PRIVATE_BUG_USER);

use Test::Mojo;
use Test::More;
use Sys::Hostname;

my $config               = get_config();
my $private_user_api_key = $config->{PRIVATE_BUG_USER . '_user_api_key'};
my $public_user_api_key  = $config->{unprivileged_user_api_key};
my $url                  = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

### Section 1: Create new private bug

my $private_bug = create_bug_fields($config);
delete $private_bug->{cc};
$private_bug->{product}          = 'QA-Selenium-TEST';
$private_bug->{component}        = 'QA-Selenium-TEST';
$private_bug->{version}          = 'QAVersion';
$private_bug->{target_milestone} = 'QAMilestone';
$private_bug->{summary}          = 'This is a private test bug';
$private_bug->{description}      = 'This is a private test bug';
$private_bug->{creator}          = $config->{PRIVATE_BUG_USER . '_user_login'};
$private_bug->{groups}           = ['QA-Selenium-TEST'];

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $private_user_api_key} => json =>
    $private_bug)->status_is(200)->json_has('/id');

my $private_bug_id = $t->tx->res->json->{id};

$t->get_ok($url
    . "rest/bug/${private_bug_id}" =>
    {'X-Bugzilla-API-Key' => $private_user_api_key})->status_is(200)
  ->json_is('/bugs/0/summary' => $private_bug->{summary});

### Section 2: Create new public bug

my $public_bug = create_bug_fields($config);
$public_bug->{summary}     = 'This is a public test bug';
$public_bug->{description} = 'This is a public test bug';
$public_bug->{creator}     = $config->{unprivileged_user_login};

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $public_user_api_key} => json =>
    $public_bug)->status_is(200)->json_has('/id');

my $public_bug_id = $t->tx->res->json->{id};

$t->get_ok($url
    . "rest/bug/${public_bug_id}" =>
    {'X-Bugzilla-API-Key' => $public_user_api_key})->status_is(200)
  ->json_is('/bugs/0/summary' => $public_bug->{summary});

### Section 3: Private bug is not visible to unprivileged user

$t->get_ok($url
    . "rest/bug/${private_bug_id}" =>
    {'X-Bugzilla-API-Key' => $public_user_api_key})->status_is(401)
  ->json_like('/message', qr/You are not authorized to access bug/);

### Section 4: Add the public bug ID as a See Also on the private bug

my $update_bug = {see_also => {add => [$public_bug_id]}};

$t->put_ok($url
    . "rest/bug/${private_bug_id}"                  =>
    {'X-Bugzilla-API-Key' => $private_user_api_key} => json => $update_bug)
  ->status_is(200)->json_has('/bugs/0/changes');

### Section 5: Private user should be able to see the public see also value on private bug

$t->get_ok($url
    . "rest/bug/${private_bug_id}?include_fields=see_also" =>
    {'X-Bugzilla-API-Key' => $private_user_api_key})->status_is(200)
  ->json_is('/bugs/0/see_also/0' => $config->{browser_url}
    . "/show_bug.cgi?id=${public_bug_id}");

### Section 6: Unprivileged user should not be able to see the see also value for private bug

$t->get_ok($url
    . "rest/bug/${public_bug_id}?include_fields=see_also" =>
    {'X-Bugzilla-API-Key' => $public_user_api_key})->status_is(200)
  ->json_hasnt('/bugs/0/see_also/0');

### Section 7: Remove the public bug ID as a See Also on the private bug

$update_bug = {see_also => {remove => [$public_bug_id]}};

$t->put_ok($url
    . "rest/bug/${private_bug_id}"                  =>
    {'X-Bugzilla-API-Key' => $private_user_api_key} => json => $update_bug)
  ->status_is(200)->json_has('/bugs/0/changes');

### Section 8: Unprivileged user should be blocked from adding the see also value for private bug

$update_bug = {see_also => {add => [$private_bug_id]}};

$t->put_ok($url
    . "rest/bug/${public_bug_id}"                  =>
    {'X-Bugzilla-API-Key' => $public_user_api_key} => json => $update_bug)
  ->status_is(401)
  ->json_like('/message', qr/You are not authorized to access bug/);

### Section 9: Unprivileged user should be blocked from adding the see also value for private bug (full URL)

$update_bug
  = {see_also =>
    {add => [$config->{browser_url} . "/show_bug.cgi?id=${private_bug_id}"]}
  };

$t->put_ok($url
    . "rest/bug/${public_bug_id}"                  =>
    {'X-Bugzilla-API-Key' => $public_user_api_key} => json => $update_bug)
  ->status_is(401)
  ->json_like('/message', qr/You are not authorized to access bug/);

### Section 10: Create a second public bug with first public bug as a see also reference

$t->post_ok($url
    . 'rest/bug' => {'X-Bugzilla-API-Key' => $public_user_api_key} => json =>
    $public_bug)->status_is(200)->json_has('/id');

my $public_bug_id_2 = $t->tx->res->json->{id};

$t->get_ok($url
    . "rest/bug/${public_bug_id_2}" =>
    {'X-Bugzilla-API-Key' => $public_user_api_key})->status_is(200)
  ->json_is('/bugs/0/summary' => $public_bug->{summary});

### Section 11: Add the first public bug as a see also value to the second public bug

$update_bug = {see_also => {add => [$public_bug_id_2]}};

$t->put_ok($url
    . "rest/bug/${public_bug_id}"                  =>
    {'X-Bugzilla-API-Key' => $public_user_api_key} => json => $update_bug)
  ->status_is(200)->json_has('/bugs/0/changes');

### Section 12: Unprivileged user should be able to see the see also value for second public bug

$t->get_ok($url
    . "rest/bug/${public_bug_id}?include_fields=see_also" =>
    {'X-Bugzilla-API-Key' => $public_user_api_key})->status_is(200)
  ->json_is('/bugs/0/see_also/0' => $config->{browser_url}
    . "/show_bug.cgi?id=${public_bug_id_2}");

done_testing();
