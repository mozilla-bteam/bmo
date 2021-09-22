# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use Cwd qw(realpath);

BEGIN {
  require lib;
  my $dir = realpath(dirname(__FILE__));
  lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}
use Mojolicious::Commands;

$ENV{MOJO_LISTEN} ||= $ENV{PORT} ? "http://*:$ENV{PORT}" : "http://*:3001";

# Start command line interface for application
Mojolicious::Commands->start_app('External::Test::API');

package External::Test::API;
use Mojo::Base 'Mojolicious';

sub startup {
  my ($self) = @_;
  my $r = $self->routes;

  # Mock the IPrepD API violations endpoint
  $r->put(
    '/violations/type/ip/*ip' => sub {
      my $c = shift;
      $c->app->defaults->{last_violation} = $c->req->json;
      $c->render(text => 'OK ', status => 200);
    }
  );
  $r->get(
    '/violations/last' => sub {
      my $c = shift;
      $c->render(json => $c->app->defaults->{last_violation}, status => 200);
    }
  );

  # Webhook endpoints for testing
  $r->post(
    '/webhooks/test/noauth' => sub {
      my $c = shift;
      $c->render(json => {ok => 1}, status => 200);
    }
  );
  $r->post(
    '/webhooks/test/withauth' => sub {
      my $c = shift;
      if ($c->req->headers->header('Authorization') eq
        'Token zQ5TSBzq7tTZMtKYq9K1ZqJMjifKx3cPL7pIGk9Q')
      {
        $c->render(json => {ok => 1}, status => 200);
      }
      else {
        $c->render(json => {ok => 0}, status => 401);
      }
    }
  );
}

1;
