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

my $config             = get_config();
my $admin_user_api_key = $config->{'admin_user_api_key'};
my $url                = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# No products specified should only include Firefox for this test
$t->get_ok(
  $url . 'rest/bmo/triage_owners' => {'X-Bugzilla-API-Key' => $admin_user_api_key})
  ->status_is(200)
  ->json_is('/Firefox/General/triage_owner', 'admin@mozilla.bugs')
  ->json_is('/Firefox/Installer/triage_owner', 'nobody@mozilla.org');

my $data = $t->tx->res->json;
use Bugzilla::Logging;
use Mojo::Util qw(dumper);
DEBUG(dumper $data);

# Get the triage owner for Firefox for only General component
$t->get_ok($url
    . 'rest/bmo/triage_owners?product=Firefox&component=General' =>
    {'X-Bugzilla-API-Key' => $admin_user_api_key})->status_is(200)
  ->json_is('/Firefox/General/triage_owner', 'admin@mozilla.bugs');

# Get the triage owner for bugzilla.mozilla.org components
$t->get_ok($url
    . 'rest/bmo/triage_owners?product=bugzilla.mozilla.org' =>
    {'X-Bugzilla-API-Key' => $admin_user_api_key})->status_is(200)
  ->json_is('/bugzilla.mozilla.org/General/triage_owner', 'admin@mozilla.bugs')
  ->json_is('/bugzilla.mozilla.org/API/triage_owner', 'automation@bmo.tld');

# Get the triage owner for components owned by admin@mozilla.bugs
$t->get_ok($url
    . 'rest/bmo/triage_owners?owner=admin@mozilla.bugs' =>
    {'X-Bugzilla-API-Key' => $admin_user_api_key})->status_is(200)
  ->json_is('/Firefox/General/triage_owner', 'admin@mozilla.bugs')
  ->json_is('/bugzilla.mozilla.org/General/triage_owner', 'admin@mozilla.bugs');

done_testing();
