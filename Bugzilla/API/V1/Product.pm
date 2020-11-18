# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Product;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::API::V1::Constants;
use Bugzilla::API::V1::Util qw(validate filter filter_wants);

use constant READ_ONLY => qw(
  get
  get_accessible_products
  get_enterable_products
  get_selectable_products
);

use constant PUBLIC_METHODS => qw(
  create
  get
  get_accessible_products
  get_enterable_products
  get_selectable_products
);

use constant FIELD_MAP =>
  {has_unconfirmed => 'allows_unconfirmed', is_open => 'isactive',};

##################################################
# Add aliases here for method name compatibility #
##################################################

BEGIN { *get_products = \&get }

# Get the ids of the products the user can search
sub get_selectable_products {
  Bugzilla->switch_to_shadow_db();
  return {ids => [map { $_->id } @{Bugzilla->user->get_selectable_products}]};
}

# Get the ids of the products the user can enter bugs against
sub get_enterable_products {
  Bugzilla->switch_to_shadow_db();
  return {ids => [map { $_->id } @{Bugzilla->user->get_enterable_products}]};
}

# Get the union of the products the user can search and enter bugs against.
sub get_accessible_products {
  Bugzilla->switch_to_shadow_db();
  return {ids => [map { $_->id } @{Bugzilla->user->get_accessible_products}]};
}

# Get a list of actual products, based on list of ids or names
our %FLAG_CACHE;

sub get {
  my ($self, $params) = validate(@_, 'ids', 'names', 'type');
  my $user = Bugzilla->user;

  Bugzilla->request_cache->{bz_etag_disable} = 1;

       defined $params->{ids}
    || defined $params->{names}
    || defined $params->{type}
    || ThrowCodeError("params_required",
    {function => "Product.get", params => ['ids', 'names', 'type']});

  Bugzilla->switch_to_shadow_db();

  my $products = [];
  if (defined $params->{type}) {
    my %product_hash;
    foreach my $type (@{$params->{type}}) {
      my $result = [];
      if ($type eq 'accessible') {
        $result = $user->get_accessible_products();
      }
      elsif ($type eq 'enterable') {
        $result = $user->get_enterable_products();
      }
      elsif ($type eq 'selectable') {
        $result = $user->get_selectable_products();
      }
      else {
        ThrowUserError('get_products_invalid_type', {type => $type});
      }
      map { $product_hash{$_->id} = $_ } @$result;
    }
    $products = [values %product_hash];
  }
  else {
    $products = $user->get_accessible_products;
  }

  my @requested_products;

  if (defined $params->{ids}) {

    # Create a hash with the ids the user wants
    my %ids = map { $_ => 1 } @{$params->{ids}};

    # Return the intersection of this, by grepping the ids from
    # accessible products.
    push(@requested_products, grep { $ids{$_->id} } @$products);
  }

  if (defined $params->{names}) {

    # Create a hash with the names the user wants
    my %names = map { lc($_) => 1 } @{$params->{names}};

    # Return the intersection of this, by grepping the names from
    # accessible products, union'ed with products found by ID to
    # avoid duplicates
    foreach my $product (grep { $names{lc $_->name} } @$products) {
      next if grep { $_->id == $product->id } @requested_products;
      push @requested_products, $product;
    }
  }

  # If we just requested a specific type of products without
  # specifying ids or names, then return the entire list.
  if (!defined $params->{ids} && !defined $params->{names}) {
    @requested_products = @$products;
  }

  # Now create a result entry for each.
  local %FLAG_CACHE = ();
  my @products = map { $self->_product_to_hash($params, $_) } @requested_products;
  return {products => \@products};
}

sub create {
  my ($self, $params) = @_;

  Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->user->in_group('editcomponents')
    || ThrowUserError("auth_failure",
    {group => "editcomponents", action => "add", object => "products"});

  # Create product
  my $args = {
    name             => $params->{name},
    description      => $params->{description},
    version          => $params->{version},
    default_bug_type => $params->{default_bug_type},
    defaultmilestone => $params->{default_milestone},

    # create_series has no default value.
    create_series => defined $params->{create_series}
    ? $params->{create_series}
    : 1
  };
  foreach my $field (qw(has_unconfirmed is_open classification)) {
    if (defined $params->{$field}) {
      my $name = FIELD_MAP->{$field} || $field;
      $args->{$name} = $params->{$field};
    }
  }
  my $product = Bugzilla::Product->create($args);
  return {id => $self->type('int', $product->id)};
}

sub _product_to_hash {
  my ($self, $params, $product) = @_;

  my $field_data = {
    id                => $self->type('int',     $product->id),
    name              => $self->type('string',  $product->name),
    description       => $self->type('string',  $product->description),
    is_active         => $self->type('boolean', $product->is_active),
    default_milestone => $self->type('string',  $product->default_milestone),
    has_unconfirmed   => $self->type('boolean', $product->allows_unconfirmed),
    classification    => $self->type('string',  $product->classification->name),
    default_bug_type  => $self->type('string',  $product->default_bug_type),
  };
  if (filter_wants($params, 'components')) {
    $field_data->{components}
      = [map { $self->_component_to_hash($_, $params) } @{$product->components}];
  }
  if (filter_wants($params, 'versions')) {
    $field_data->{versions}
      = [map { $self->_version_to_hash($_, $params) } @{$product->versions}];
  }
  if (filter_wants($params, 'milestones')) {
    $field_data->{milestones}
      = [map { $self->_milestone_to_hash($_, $params) } @{$product->milestones}];
  }

  # BMO - add default hw/os
  $field_data->{default_platform}
    = $self->type('string', $product->default_platform);
  $field_data->{default_op_sys} = $self->type('string', $product->default_op_sys);

  # BMO - add default security group
  $field_data->{default_security_group}
    = $self->type('string', $product->default_security_group);
  return filter($params, $field_data);
}

sub _component_to_hash {
  my ($self, $component, $params) = @_;
  my $field_data = filter $params, {
    id          => $self->type('int',    $component->id),
    name        => $self->type('string', $component->name),
    description => $self->type('string', $component->description),
    default_assigned_to =>
      $self->type('email', $component->default_assignee->login),
    default_qa_contact =>
      $self->type('email', $component->default_qa_contact->login),
    triage_owner => $self->type('email', $component->triage_owner->login),
    sort_key =>    # sort_key is returned to match Bug.fields
      0,
    is_active => $self->type('boolean', $component->is_active),
    default_bug_type => $self->type('string', $component->default_bug_type),
    },
    undef, 'components';

  if (filter_wants($params, 'flag_types', undef, 'components')) {
    $field_data->{flag_types} = {
      bug => [
        map { $FLAG_CACHE{$_->id} //= $self->_flag_type_to_hash($_) }
          @{$component->flag_types->{'bug'}}
      ],
      attachment => [
        map { $FLAG_CACHE{$_->id} //= $self->_flag_type_to_hash($_) }
          @{$component->flag_types->{'attachment'}}
      ],
    };
  }

  return $field_data;
}

sub _flag_type_to_hash {
  my ($self, $flag_type) = @_;
  return {
    id               => $self->type('int',     $flag_type->id),
    name             => $self->type('string',  $flag_type->name),
    description      => $self->type('string',  $flag_type->description),
    cc_list          => $self->type('string',  $flag_type->cc_list),
    sort_key         => $self->type('int',     $flag_type->sortkey),
    is_active        => $self->type('boolean', $flag_type->is_active),
    is_requestable   => $self->type('boolean', $flag_type->is_requestable),
    is_requesteeble  => $self->type('boolean', $flag_type->is_requesteeble),
    is_multiplicable => $self->type('boolean', $flag_type->is_multiplicable),
    grant_group      => $self->type('int',     $flag_type->grant_group_id),
    request_group    => $self->type('int',     $flag_type->request_group_id),
  };
}

sub _version_to_hash {
  my ($self, $version, $params) = @_;
  return filter $params, {
    id   => $self->type('int',    $version->id),
    name => $self->type('string', $version->name),
    sort_key =>    # sort_key is returened to match Bug.fields
      0,
    is_active => $self->type('boolean', $version->is_active),
    },
    undef, 'versions';
}

sub _milestone_to_hash {
  my ($self, $milestone, $params) = @_;
  return filter $params,
    {
    id        => $self->type('int',     $milestone->id),
    name      => $self->type('string',  $milestone->name),
    sort_key  => $self->type('int',     $milestone->sortkey),
    is_active => $self->type('boolean', $milestone->is_active),
    },
    undef, 'milestones';
}

1;
