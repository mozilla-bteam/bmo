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

  # Remove current graveyard products from product list we do
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

  # Check if user can edit graveyard product and that it exists
  my $graveyard_product_name = "$product_name Graveyard";
  my $graveyard_product
    = Bugzilla::Product->new({name => $graveyard_product_name});
  if ($graveyard_product) {
    if ( !$user->in_group('editcomponents', $graveyard_product->id)
      || !$user->can_see_product($graveyard_product->name))
    {
      push @error_list,
        "Your account is not permitted to administer components for graveyard product '$graveyard_product_name'.";
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
        . "graveyard product '$graveyard_product_name'.",
      "Versions will be syncronized from source product '$product_name' to "
        . "graveyard product '$graveyard_product_name'.",
      "Security groups will be syncronized from source product '$product_name' to "
        . "graveyard product '$graveyard_product_name'.",
      "Regular flags will be syncronized from source product '$product_name' to "
        . "graveyard product '$graveyard_product_name'.",
      "Tracking flags will be syncronized from source product '$product_name' to "
        . "graveyard product '$graveyard_product_name'.",
      "The component '$component_name' will be moved from source product '$product_name'"
        . " to graveyard product '$graveyard_product_name'.",
    );
    $vars->{confirm_list} = \@confirm_list;
  }

  # Perform the component move operations
  if (!@error_list && $self->param('do_the_move')) {
    my @move_list;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    # Syncing of milestones and versions
    $dbh->do('
      INSERT INTO milestones(value, sortkey, isactive, product_id)
        SELECT m1.value, m1.sortkey, m1.isactive, ?
          FROM milestones m1
               LEFT JOIN milestones m2 ON m1.value = m2.value
               AND m2.product_id = ?
         WHERE m1.product_id = ? AND m2.value IS NULL', undef,
      $graveyard_product->id, $graveyard_product->id, $product->id);

    push @move_list,
      "Milestones syncronized from source product '$product_name' to "
      . "graveyard product '$graveyard_product_name'.";

    $dbh->do('
      INSERT INTO versions(value, isactive, product_id)
        SELECT v1.value, v1.isactive, ?
          FROM versions v1
               LEFT JOIN versions v2 ON v1.value = v2.value AND v2.product_id = ?
         WHERE v1.product_id = ? AND v2.value IS NULL', undef,
      $graveyard_product->id, $graveyard_product->id, $product->id);

    push @move_list, "Versions syncronized from source product '$product_name' to "
      . "graveyard product '$graveyard_product_name'.";

    $dbh->do('
      INSERT INTO group_control_map (group_id, product_id, entry, membercontrol,
             othercontrol, canedit, editcomponents,
             editbugs, canconfirm)
        SELECT g1.group_id, ?, g1.entry, g1.membercontrol, g1.othercontrol,
               g1.canedit, g1.editcomponents, g1.editbugs, g1.canconfirm
          FROM group_control_map g1
               LEFT JOIN group_control_map g2 ON g1.product_id = ?
               AND g2.product_id = ? AND g1.group_id = g2.group_id
         WHERE g1.product_id = ? AND g2.group_id IS NULL', undef,
      $graveyard_product->id, $product->id, $graveyard_product->id, $product->id);

    push @move_list,
      "Security groups syncronized from source product '$product_name' to "
      . "graveyard product '$graveyard_product_name'.";

    # Sync normal flags such as bug flags and attachment flags
    $dbh->do('
      INSERT INTO flaginclusions(component_id, type_id, product_id)
        SELECT fi1.component_id, fi1.type_id, ? FROM flaginclusions fi1
               LEFT JOIN flaginclusions fi2
               ON fi1.type_id = fi2.type_id
               AND fi2.product_id = ?
         WHERE fi1.product_id = ? AND fi2.type_id IS NULL', undef,
      $graveyard_product->id, $graveyard_product->id, $product->id);

    push @move_list,
      "Regular flags syncronized from source product '$product_name' to "
      . "graveyard product '$graveyard_product_name'.";

    # Sync tracking type flags""
    $dbh->do('
      INSERT INTO tracking_flags_visibility (tracking_flag_id, product_id, component_id)
        SELECT tf1.tracking_flag_id, ?, tf1.component_id FROM tracking_flags_visibility tf1
               LEFT JOIN tracking_flags_visibility tf2
               ON tf1.tracking_flag_id = tf2.tracking_flag_id
               AND tf2.product_id = ?
         WHERE tf1.product_id = ? AND tf2.tracking_flag_id IS NULL', undef,
      $graveyard_product->id, $graveyard_product->id, $product->id);

    push @move_list,
      "Tracking flags syncronized from source product '$product_name' to "
      . "graveyard product '$graveyard_product_name'.";

    # Grab list of bug ids that will be affected
    my $ra_ids
      = $dbh->selectcol_arrayref(
      'SELECT bug_id FROM bugs WHERE product_id = ? AND component_id = ?',
      undef, $product->id, $component->id);

    # Update the bugs table
    $dbh->do('UPDATE bugs SET product_id = ? WHERE component_id = ?',
      undef, $graveyard_product->id, $component->id);

    # Update the flags tables
    fix_flags('flaginclusions', $graveyard_product, $component);
    fix_flags('flagexclusions', $graveyard_product, $component);

    # Update the components table
    $dbh->do('UPDATE components SET product_id = ? WHERE id = ?',
      undef, $graveyard_product->id, $component->id);

    Bugzilla::Hook::process(
      'reorg_move_component',
      {
        old_product => $product,
        new_product => $graveyard_product,
        component   => $component,
      }
    );

    # Mark bugs as touched
    $dbh->do('UPDATE bugs SET delta_ts = NOW() WHERE component_id = ?',
      undef, $component->id);
    $dbh->do('UPDATE bugs SET lastdiffed = NOW() WHERE component_id = ?',
      undef, $component->id);

    # Update bugs_activity
    my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
    Bugzilla->set_user($auto_user);

    $dbh->do('
      INSERT INTO bugs_activity(bug_id, who, bug_when, fieldid, removed, added)
        SELECT bug_id, ?, delta_ts, ?, ?, ?
          FROM bugs WHERE component_id = ?', undef, $auto_user->id,
      get_field_id('product'), $product_name, $graveyard_product_name,
      $component->id);

    Bugzilla::Hook::process('reorg_move_bugs', {bug_ids => $ra_ids});

    $dbh->bz_commit_transaction();

    # It's complex to determine which items now need to be flushed from memcached.
    # As this is expected to be a rare event, we just flush the entire cache.
    Bugzilla->memcached->clear_all();

    # Now that we know the component and product, display a list of
    # changes that will be made or errors that need to be addressed.
    push @move_list, "Component '$component_name' successfully moved from source "
      . "product '$product_name' to graveyard product '$graveyard_product_name'.";

    $vars->{move_list} = \@move_list;
  }

  $vars->{token} = issue_session_token('component_graveyard');
  $self->stash(%{$vars});
  return $self->render('admin/components/graveyard', handler => 'bugzilla');
}

sub fix_flags {
  my ($table, $new_product, $component) = @_;
  my $dbh = Bugzilla->dbh;

  my $type_ids
    = $dbh->selectcol_arrayref(
    "SELECT DISTINCT type_id FROM $table WHERE component_id = ?",
    undef, $component->id);
  $dbh->do("DELETE FROM $table WHERE component_id = ?", undef, $component->id);
  foreach my $type_id (@$type_ids) {
    $dbh->do(
      "INSERT INTO $table (type_id, product_id, component_id) VALUES (?, ?, ?)",
      undef, ($type_id, $new_product->id, $component->id));
  }
}

1;
