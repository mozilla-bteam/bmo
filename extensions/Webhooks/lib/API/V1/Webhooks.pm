# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Webhooks::API::V1::Webhooks;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Extension::Webhooks::Webhook;

use Mojo::JSON qw(true false);

sub setup_routes {
  my ($class, $r) = @_;
  my $routes = $r->under(
    '/webhooks' => sub { Bugzilla->usage_mode(USAGE_MODE_MOJO_REST); });
  $routes->get('/list')->to('Webhooks::API::V1::Webhooks#list');
}

sub list {
  my $self = shift;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);
  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  my $webhooks
    = Bugzilla::Extension::Webhooks::Webhook->match({user_id => $user->id});

  my @results;
  foreach my $webhook (@{$webhooks}) {
    push @results, $self->_webhook_to_hash($webhook);
  }

  return $self->render(json => {webhooks => \@results});
}

sub _webhook_to_hash {
  my ($self, $webhook) = @_;

  my $connector
    = Bugzilla->push_ext->connectors->by_name('Webhook_' . $webhook->id);

  my $data = {
    id        => $webhook->id,
    creator   => $webhook->user->login,
    name      => $webhook->name,
    url       => $webhook->url,
    event     => $webhook->event,
    product   => $webhook->product_name,
    component => $webhook->component_name,
    enabled   => ($connector->enabled ? true : false),
    errors    => $connector->backlog->count,
  };

  return $data;
}

1;
