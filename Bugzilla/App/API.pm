# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::API;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Mojo::Loader qw( find_modules );
use Module::Runtime qw(require_module);
use Try::Tiny;

use Bugzilla::Constants;
use Bugzilla::Logging;

use constant SUPPORTED_VERSIONS => qw(V1);

sub setup_routes {
  my ($class, $r) = @_;

  # Add Bugzilla::API to namespaces for searching for controllers
  my $namespaces = $r->namespaces;
  push @$namespaces, 'Bugzilla::API';
  $r->namespaces($namespaces);

  # Backwards compat with /api/user/profile which Phabricator
  $r->under('/api' => sub { Bugzilla->usage_mode(USAGE_MODE_REST); })
    ->get('/user/profile')->to('V1::User#user_profile');

  # Other backwards compat routes
  $r->under('/latest' => sub { Bugzilla->usage_mode(USAGE_MODE_REST); })
    ->get('/configuration')->to('V1::Configuration#configuration');
  $r->under('/bzapi' => sub { Bugzilla->usage_mode(USAGE_MODE_REST); })
    ->get('/configuration')->to('V1::Configuration#configuration');

  # Set the usage mode for all routes under /rest
  my $rest_routes
    = $r->under('/rest' => sub { Bugzilla->usage_mode(USAGE_MODE_REST); });

  foreach my $version (SUPPORTED_VERSIONS) {
    foreach my $module (find_modules("Bugzilla::API::$version")) {
      try {
        require_module($module);
        my $controller = $module->new;
        if ($controller->can('setup_routes')) {
          $controller->setup_routes($rest_routes);
        }
      }
      catch {
        WARN("$module could not be loaded");
      };
    }
  }
}

1;
