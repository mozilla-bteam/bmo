# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#############################################
# Tests for REST calls in Classification.pm #
#############################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use QA::Util qw(get_config);

use Test::Mojo;
use Test::More;

my $config           = get_config();
my $admin_api_key    = $config->{admin_user_api_key};
my $editbugs_api_key = $config->{editbugs_user_api_key};
my $url              = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();

# Admins can always access classifications, even when they are disabled.
$t->get_ok(
  $url . 'rest/classification/1' => {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200)->json_has('/classifications');
my $class = $t->tx->res->json->{classifications}->[0];
ok($class->{id},
      "Admin found classification '"
    . $class->{name}
    . "' with the description '"
    . $class->{description}
    . "'");
my @products = sort map { $_->{name} } @{$class->{products}};
ok(scalar(@products),
  scalar(@products) . ' product(s) found: ' . join(', ', @products));

$t->get_ok($url
    . 'rest/classification/Class2_QA' => {'X-Bugzilla-API-Key' => $admin_api_key})
  ->status_is(200)->json_has('/classifications');
$class = $t->tx->res->json->{classifications}->[0];
ok($class->{id},
      "Admin found classification '"
    . $class->{name}
    . "' with the description '"
    . $class->{description}
    . "'");
@products = sort map { $_->{name} } @{$class->{products}};
ok(scalar(@products),
  scalar(@products) . ' product(s) found: ' . join(', ', @products));

# When classifications are enabled, everybody can query classifications...
# ... including logged-out users.
$t->get_ok($url . 'rest/classification/1')->status_is(200)
  ->json_has('/classifications');
$class = $t->tx->res->json->{classifications}->[0];
ok($class->{id},
  'Logged-out users can access classification ' . $class->{name});

# ... and non-admins.
$t->get_ok(
  $url . 'rest/classification/1' => {'X-Bugzilla-API-Key' => $editbugs_api_key})
  ->status_is(200)->json_has('/classifications');
$class = $t->tx->res->json->{classifications}->[0];
ok($class->{id}, 'Non-admins can access classification ' . $class->{name});

done_testing();
