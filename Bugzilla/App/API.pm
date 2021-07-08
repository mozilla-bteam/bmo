# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::API;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use File::Basename qw(basename);
use Mojo::Loader qw( find_modules );
use Module::Runtime qw(require_module);
use Try::Tiny;

use Bugzilla::Constants;
use Bugzilla::Logging;

use constant SUPPORTED_VERSIONS => qw(V1);

sub setup_routes {
  my ($class, $r) = @_;

  # Add Bugzilla::API and Bugzilla::Extension to
  # namespaces for searching for API controllers
  my $namespaces = $r->namespaces;
  push @$namespaces, 'Bugzilla::API', 'Bugzilla::Extension';
  $r->namespaces($namespaces);

  # Backwards compat with /api/user/profile which Phabricator requires
  $r->under(
    '/api' => sub {
      my ($c) = @_;
      _insert_rest_headers($c);
      Bugzilla->usage_mode(USAGE_MODE_REST);
    }
  )->get('/user/profile')->to('V1::User#user_profile');

  # Other backwards compat routes
  $r->under(
    '/latest' => sub {
      my ($c) = @_;
      _insert_rest_headers($c);
      Bugzilla->usage_mode(USAGE_MODE_REST);
    }
  )->get('/configuration')->to('V1::Configuration#configuration');
  $r->under(
    '/bzapi' => sub {
      my ($c) = @_;
      _insert_rest_headers($c);
      Bugzilla->usage_mode(USAGE_MODE_REST);
    }
  )->get('/configuration')->to('V1::Configuration#configuration');

  # Set the usage mode for all routes under /rest
  my $rest_routes = $r->under(
    '/rest' => sub {
      my ($c) = @_;
      _insert_rest_headers($c);
      Bugzilla->usage_mode(USAGE_MODE_REST);
    }
  );

  # Standard API support
  foreach my $version (SUPPORTED_VERSIONS) {
    foreach my $module (find_modules("Bugzilla::API::$version")) {
      _load_api_module($rest_routes, $module);
    }
  }

  # Extension API support
  my @ext_paths     = glob bz_locations()->{'extensionsdir'} . '/*';
  my @ext_api_paths = grep { !-e "$_/disabled" && -d "$_/lib/API" } @ext_paths;

  foreach my $version (SUPPORTED_VERSIONS) {
    foreach my $ext_path (@ext_api_paths) {
      my $ext_name = $ext_path;
      $ext_name =~ s|^.*extensions/||;

      my @module_paths = glob "$ext_path/lib/API/$version/*";
      foreach my $module_path (@module_paths) {
        my $module = "Bugzilla::Extension::${ext_name}::API::${version}::"
          . basename($module_path, '.pm');
        _load_api_module($rest_routes, $module);
      }
    }
  }
}

sub _load_api_module {
  my ($routes, $module) = @_;
  try {
    require_module($module);
    my $controller = $module->new;
    if ($controller->can('setup_routes')) {
      $controller->setup_routes($routes);
    }
  }
  catch {
    WARN("$module could not be loaded");
  };
}

sub _insert_rest_headers {
  my ($c) = @_;

  # Access Control
  my @allowed_headers
    = qw(accept authorization content-type origin user-agent x-bugzilla-api-key x-requested-with);
  $c->res->headers->header('Access-Control-Allow-Origin' => '*');
  $c->res->headers->header(
    'Access-Control-Allow-Headers' => join ', ',
    @allowed_headers
  );
}

1;
