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
use Bugzilla::Error;
use Bugzilla::API::V1::Util qw(filter validate params_to_objects);

sub get {
  my ($self, $params) = validate(@_, 'names', 'ids');

  defined $params->{names}
    || defined $params->{ids}
    || ThrowCodeError('params_required',
    {function => 'Classification.get', params => ['names', 'ids']});

  my $user = Bugzilla->user;

  Bugzilla->params->{'useclassification'}
    || $user->in_group('editclassifications')
    || ThrowUserError('auth_classification_not_enabled');

  Bugzilla->switch_to_shadow_db;

  my @classification_objs
    = @{params_to_objects($params, 'Bugzilla::Classification')};
  unless ($user->in_group('editclassifications')) {
    my %selectable_class
      = map { $_->id => 1 } @{$user->get_selectable_classifications};
    @classification_objs = grep { $selectable_class{$_->id} } @classification_objs;
  }

  my @classifications
    = map { $self->_classification_to_hash($_, $params) } @classification_objs;

  return {classifications => \@classifications};
}

sub _classification_to_hash {
  my ($self, $classification, $params) = @_;

  my $user = Bugzilla->user;
  return
    unless (Bugzilla->params->{'useclassification'}
    || $user->in_group('editclassifications'));

  my $products
    = $user->in_group('editclassifications')
    ? $classification->products
    : $user->get_selectable_products($classification->id);

  return filter $params,
    {
    id          => $self->type('int',    $classification->id),
    name        => $self->type('string', $classification->name),
    description => $self->type('string', $classification->description),
    sort_key    => $self->type('int',    $classification->sortkey),
    products => [map { $self->_product_to_hash($_, $params) } @$products],
    };
}

sub _product_to_hash {
  my ($self, $product, $params) = @_;

  return filter $params,
    {
    id          => $self->type('int',    $product->id),
    name        => $self->type('string', $product->name),
    description => $self->type('string', $product->description),
    },
    undef, 'products';
}

1;
