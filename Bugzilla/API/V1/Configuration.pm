# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Configuration;

use 5.10.1;

use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Keyword;
use Bugzilla::Logging;
use Bugzilla::Product;
use Bugzilla::Status;

use List::MoreUtils qw(any);
use Mojo::Base qw( Mojolicious::Controller );
use Mojo::JSON qw( true false );

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/latest/configuration')->to('V1::Configuration#configuration');
  $r->get('/rest/configuration')->to('V1::Configuration#configuration');
  $r->get('/bzapi/configuration')->to('V1::Configuration#configuration');
}

sub configuration {
  my ($self) = @_;
  my $user = $self->bugzilla->login;

  my $can_cache = !$user->id && !$self->param('product') && !$self->param('flags');

  # Using config.* will clear this data in memcache when Bugzilla changes are made to products, components, etc.
  my $cache_key = 'config.configuration';
  if ($can_cache) {
    my $result = Bugzilla->memcached->get_config({key => $cache_key});
    return $self->render(json => $result) if defined $result;
  }

  # Get data from the shadow DB as they don't change very often.
  Bugzilla->switch_to_shadow_db;

  # Information about this instance of Bugzilla
  my %result = (
    version             => BUGZILLA_VERSION,
    maintainer          => Bugzilla->params->{maintainer},
    announcement        => Bugzilla->params->{announcehtml},
    max_attachment_size => Bugzilla->params->{maxattachmentsize} * 1000,
  );

  my %all_flag_types;
  my %all_groups;

  # Classifications
  my %cl_name_for;
  my %classifications;
  if (Bugzilla->params->{useclassification}) {
    foreach my $cl (@{$user->get_selectable_classifications}) {
      $cl_name_for{$cl->id}       = $cl->name;
      $classifications{$cl->name} = {
        id          => $cl->id,
        description => $cl->description,
        products    => [map { $_->name } @{$user->get_selectable_products}]
      };
    }
  }
  $result{classification} = \%classifications;

  # Products
  my %products;
  foreach my $product (@{$user->get_selectable_products}) {
    $products{$product->name} = {
      id                        => $product->id,
      description               => $product->description,
      is_active                 => $product->is_active ? true : false,
      is_permitting_unconfirmed => $product->allows_unconfirmed ? true : false,
    };

    if (Bugzilla->params->{useclassification}) {
      $products{$product->name}->{classification}
        = $cl_name_for{$product->classification_id};
    }

    # Components
    my %components;
    foreach my $component (@{$product->components}) {
      $components{$component->name} = {
        id          => $component->id,
        description => $component->description,
        is_active   => $component->is_active ? true : false,
      };
      if ($self->param('flags')) {
        my $flag_types = $component->flag_types({is_active => 1});
        map { $all_flag_types{$_->id} = $_ } @{$flag_types->{bug}},
          @{$flag_types->{attachment}};
        $components{$component->name}->{flag_type}
          = [map { $_->id } @{$flag_types->{bug}}, @{$flag_types->{attachment}}];
      }
    }
    $products{$product->name}->{component} = \%components;

    # Versions
    my %versions;
    foreach my $version (@{$product->versions}) {
      $versions{$version->name} = {
        id        => $version->id,
        name      => $version->name,
        is_active => $version->is_active ? true : false,
      };
    }
    $products{$product->name}->{version}        = [keys %versions];
    $products{$product->name}->{version_detail} = [values %versions];

    # Target milestones
    if (Bugzilla->params->{usetargetmilestone}) {
      $products{$product->name}->{default_target_milestone}
        = $product->default_milestone;
      my %milestones;
      foreach my $milestone (@{$product->milestones}) {
        $milestones{$milestone->name} = {
          id        => $milestone->id,
          name      => $milestone->name,
          sortkey   => $milestone->sortkey,
          is_active => $milestone->is_active ? true : false,
        };
      }
      $products{$product->name}->{target_milestone}        = [keys %milestones];
      $products{$product->name}->{target_milestone_detail} = [values %milestones];
    }

    # Available groups for this product
    map { $all_groups{$_->id} = $_ } @{$product->groups_available};
    $products{$product->name}->{group}
      = [map { $_->id } @{$product->groups_available}];
  }
  $result{product} = \%products;

  # Overall flags
  if ($self->param('flags')) {
    my %flag_types;
    foreach my $type_id (keys %all_flag_types) {
      my $type = $all_flag_types{$type_id};
      $flag_types{$type_id} = {
        name                        => $type->name,
        description                 => $type->description,
        is_for_bugs                 => $type->target_type eq 'bug' ? true : false,
        is_requestable              => $type->is_requestable ? true : false,
        is_specifically_requestable => $type->is_requesteeble ? true : false,
        is_multiplicable            => $type->is_multiplicable ? true : false,
      };
      if ($user->in_group('editcomponents')) {
        if ($type->request_group_id) {
          $flag_types{$type_id}->{request_group} = $type->request_group_id;
        }
        if ($type->grant_group_id) {
          $flag_types{$type_id}->{grant_group} = $type->grant_group_id;
        }
      }
    }
    $result{flag_type} = \%flag_types;
  }

  # Overall groups
  my %groups;
  foreach my $group_id (keys %all_groups) {
    my $group = $all_groups{$group_id};
    $groups{$group_id} = {
      name              => $group->name,
      description       => $group->description,
      is_accepting_bugs => $group->is_bug_group ? true : false,
      is_active         => $group->is_active ? true : false,
    };
  }
  $result{group} = \%groups;

  # Generate a list of fields non-obsolete fields
  my @all_fields = @{Bugzilla::Field->match({obsolete => 0})};

  # Exclude fields the user cannot see.
  if (!$user->is_timetracker) {
    @all_fields = grep {
      $_->name
        !~ /^(estimated_time|remaining_time|work_time|percentage_complete|deadline)$/
    } @all_fields;
  }

  # Tracking flag field values
  my %tracking_flag_values;
  foreach my $field (Bugzilla->active_custom_fields()) {
    next if $field->type != FIELD_TYPE_EXTENSION;
    $tracking_flag_values{$field->name}
      = [map { $_->value } @{$field->legal_values}];
  }

  # Convert internal field names to API names
  my %fields;
  my %api_field_names = reverse %{Bugzilla::Bug::FIELD_MAP()};
  $api_field_names{'bug_group'} = 'groups';

  # Built-in fields do not have type IDs. There aren't ID values for all
  # the types of the built-in fields, but we do what we can, and leave the
  # rest as "0" (unknown).
  my %type_id_for = (
    'id'                      => 6,
    'summary'                 => 1,
    'classification'          => 2,
    'version'                 => 2,
    'url'                     => 1,
    'whiteboard'              => 1,
    'keywords'                => 3,
    'component'               => 2,
    'attachment.description'  => 1,
    'attachment.file_name'    => 1,
    'attachment.content_type' => 1,
    'target_milestone'        => 2,
    'comment'                 => 4,
    'alias'                   => 1,
    'deadline'                => 5,
  );

  foreach my $field (@all_fields) {
    my $name = $api_field_names{$field->name} || $field->name;
    $fields{$name} = {
      description => $field->description,
      is_active   => true,
      type        => $field->type || $type_id_for{$name} || 0,
    };

    if ($name eq 'status') {
      my @open_status;
      my @closed_status;
      foreach my $status (@{get_legal_field_values('bug_status')}) {
        is_open_state($status) ? push @open_status, $status : push @closed_status,
          $status;
      }
      $fields{$name}->{open}   = \@open_status;
      $fields{$name}->{closed} = \@closed_status;
      $fields{$name}->{transitions}
        = {'{Start}' => [map { $_->name } @{Bugzilla::Status->can_change_to}]};
      foreach my $status (Bugzilla::Status->get_all) {
        my $targets = $status->can_change_to;
        $fields{$name}->{transitions}->{$status->name} = [map { $_->name } @{$targets}];
      }
    }

    if ($field->custom) {
      $fields{$name}->{is_on_bug_entry} = $field->enter_bug ? true : false;
    }

    if (
      any { $_ eq $name }
      qw(type priority severity platform op_sys status resolution)
      )
    {
      $fields{$name}->{values} = get_legal_field_values($field->name);
    }
    elsif ($name eq 'keywords') {
      $fields{$name}->{values} = [map { $_->name } Bugzilla::Keyword->get_all];
    }
    elsif ($tracking_flag_values{$field->name}) {
      $fields{$name}->{values} = $tracking_flag_values{$field->name};
    }
    elsif ($field->is_select) {
      $fields{$name}->{values} = $field->legal_values;
    }
  }
  $result{field} = \%fields;

  if ($can_cache) {
    Bugzilla->memcached->set_config({key => $cache_key, data => \%result});
  }

  return $self->render(json => \%result);
}

1;
