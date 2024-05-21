# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::BMO::ComponentGraveyard;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Hook;
use Bugzilla::Logging;
use Bugzilla::Product;
use Bugzilla::Token;
use Bugzilla::Util;

sub setup_routes {
  my ($class, $r) = @_;
  $r->any('/admin/component/graveyard')->to('BMO::ComponentGraveyard#graveyard')
    ->name('component_graveyard');
}

sub graveyard {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO);
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) || return undef;

  my $editcomponents    = $user->in_group('editcomponents');
  my $editable_products = $user->get_products_by_permission('editcomponents');

  $editcomponents
    || scalar @{$editable_products}
    || return $self->user_error('auth_failure',
    {group => 'editcomponents', action => 'edit', object => 'components'});

  # # Discover all provided parameters such as component and product
  my $product_name   = $self->param('product')   || '';
  my $component_name = $self->param('component') || '';
  my $token          = $self->param('token');

  if ($self->req->method eq 'POST') {
    my $post_params = $self->req->body_params->to_hash;
    $product_name   = $post_params->{product}   || '';
    $component_name = $post_params->{component} || '';
    $token          = $post_params->{token};
  }

  # If the user has editcomponents privs, then we include
  # all selectable products
  if ($editcomponents) {
    $editable_products = $user->get_selectable_products;
  }

  # Remove current destination products from product list we do
  # not want to move components out of the graveyard
  $editable_products = [grep { $_->name !~ /Graveyard$/ } @{$editable_products}];

  my $vars = {editable_products => $editable_products,};
  $vars->{selected_product}   = $product_name   if $product_name;
  $vars->{selected_component} = $component_name if $component_name;

  # Redisplay the product/component selection form if a product
  # and component were not selected
  if (!$product_name || !$component_name) {
    $vars->{token} = issue_session_token('component_graveyard');
    $self->stash(%{$vars});
    return $self->render(
      template => 'admin/components/graveyard',
      handler  => 'bugzilla'
    );
  }

  # Handle CSRF tokens
  check_token_data($token, 'component_graveyard');
  delete_token($token);

  # Sanity checks first
  my @error_list;

  # Check if user can edit current product
  my $product = Bugzilla::Product->new({name => $product_name});
  if ($product) {
    if ( !$user->in_group('editcomponents', $product->id)
      || !$user->can_see_product($product->name))
    {
      push @error_list,
        "Your account is not permitted to administer components for source product '$product_name'.";
    }
  }
  else {
    push @error_list, "Source product '$product_name' was not found.";
  }

  # Check if user can edit destination product and that it exists
  my $graveyard_product_name = "$product_name Graveyard";
  my $graveyard_product
    = Bugzilla::Product->new({name => $graveyard_product_name});
  if ($graveyard_product) {
    if ( !$user->in_group('editcomponents', $graveyard_product->id)
      || !$user->can_see_product($graveyard_product->name))
    {
      push @error_list,
        "Your account is not permitted to administer components for destination product '$graveyard_product_name'.";
    }
  }
  else {
    push @error_list, "Graveyard product '$graveyard_product_name' was not found.";
  }

  my $component
    = Bugzilla::Component->new({product => $product, name => $component_name});
  if ($component) {

    # If component has open bugs, we cannot continue
    my $open_bugs
      = Bugzilla::Bug->match({component_id => $component->id, resolution => ''});
    if (my $count = scalar @{$open_bugs}) {
      push @error_list,
        "There are $count open bugs for source product '$product_name' and component '$component_name'. "
        . 'These will need to be closed first.';
    }
  }
  else {
    push @error_list,
      "Component '$component_name' does not exist for source product '$product_name'.";
  }

  $vars->{error_list} = \@error_list if @error_list;

  # Confirm the changes that will be made before continuing
  if (!@error_list && $self->param('confirm_move')) {
    my @confirm_list = (
      "Milestones will be syncronized from source product '$product_name' to "
        . "destination product '$graveyard_product_name'.",
      "Versions will be syncronized from source product '$product_name' to "
        . "destination product '$graveyard_product_name'.",
      "Security groups will be syncronized from source product '$product_name' to "
        . "destination product '$graveyard_product_name'.",
      "Regular flags will be syncronized from source product '$product_name' to "
        . "destination product '$graveyard_product_name'.",
      "Tracking flags will be syncronized from source product '$product_name' to "
        . "destination product '$graveyard_product_name'.",
      "The component '$component_name' will be moved from source product '$product_name'"
        . " to destination product '$graveyard_product_name'.",
    );
    $vars->{confirm_list} = \@confirm_list;
  }

  # Perform the component move operations
  if (!@error_list && $self->param('do_the_move')) {
     my @move_list = $component->move_to_graveyard_product($graveyard_product);
     $vars->{move_list} = \@move_list;
  }

  $vars->{token} = issue_session_token('component_graveyard');
  $self->stash(%{$vars});
  return $self->render('admin/components/graveyard', handler => 'bugzilla');
}

1;
