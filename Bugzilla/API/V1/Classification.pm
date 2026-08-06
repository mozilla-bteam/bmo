# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Classification;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Classification;
use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;
  my $class_routes = $r->under(
    '/classification' => sub { Bugzilla->usage_mode(USAGE_MODE_MOJO_REST); });
  $class_routes->get('/:id_or_name')->to('V1::Classification#get');
}

sub get {
  my ($self) = @_;

  my $user = $self->bugzilla->login;

  Bugzilla->params->{useclassification}
    || $user->in_group('editclassifications')
    || return $self->user_error('auth_classification_not_enabled');

  Bugzilla->switch_to_shadow_db;

  my $id_or_name = $self->param('id_or_name');
  my $classification = Bugzilla::Classification->check(
    $id_or_name =~ /^\d+$/ ? {id => $id_or_name} : $id_or_name);

  my @classifications;
  if ($user->in_group('editclassifications')
    || grep { $_->id == $classification->id }
    @{$user->get_selectable_classifications})
  {
    @classifications = ($self->_classification_to_hash($classification, $user));
  }

  return $self->render(json => {classifications => \@classifications});
}

sub _classification_to_hash {
  my ($self, $classification, $user) = @_;

  my $products
    = $user->in_group('editclassifications')
    ? $classification->products
    : $user->get_selectable_products($classification->id);

  return {
    id          => $classification->id,
    name        => $classification->name,
    description => $classification->description,
    sort_key    => $classification->sortkey,
    products    => [map { $self->_product_to_hash($_) } @$products],
  };
}

sub _product_to_hash {
  my ($self, $product) = @_;

  return {
    id          => $product->id,
    name        => $product->name,
    description => $product->description,
  };
}

1;
