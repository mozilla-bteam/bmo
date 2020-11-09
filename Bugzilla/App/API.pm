# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::API;

use 5.10.1;
use Bugzilla::Logging;
use Module::Runtime qw(require_module);
use Mojo::Base qw( Mojolicious::Controller );
use Mojo::Loader qw( find_modules );
use Try::Tiny;

use constant SUPPORTED_VERSIONS => qw(V1);

use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;

  # Add Bugzilla::API to namespaces for searching for controllers
  my $namespaces = $r->namespaces;
  push @$namespaces, 'Bugzilla::API';
  $r->namespaces($namespaces);

  foreach my $version (SUPPORTED_VERSIONS) {
    foreach my $module (find_modules("Bugzilla::API::$version")) {
      try {
        require_module($module);
        my $controller = $module->new;
        if ($controller->can('setup_routes')) {
          $controller->setup_routes($r);
        }
      }
      catch {
        WARN("$module could not be loaded");
      };
    }
  }
}

1;
