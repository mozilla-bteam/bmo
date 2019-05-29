# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::Extension::TrackingFlags::Admin;

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BMO::Data;
use Bugzilla::Field;
use Bugzilla::Install::Filesystem;
use Bugzilla::Product;

use JSON;
use List::MoreUtils qw(none);

our $VERSION = '1';
our @FLAG_CACHE;

BEGIN {
  *Bugzilla::tracking_flags      = \&_tracking_flags;
  *Bugzilla::tracking_flag_names = \&_tracking_flag_names;
}

sub _tracking_flags {
  return Bugzilla::Extension::TrackingFlags::Flag->get_all();
}

sub _tracking_flag_names {
  my ($class)   = @_;
  my $memcached = $class->memcached;
  my $cache     = $class->request_cache;
  my $tf_names  = $cache->{tracking_flags_names};

  return @$tf_names if $tf_names;
  $tf_names //= $memcached->get_config({key => 'tracking_flag_names'});
  $tf_names //= Bugzilla->dbh->selectcol_arrayref(
    "SELECT name FROM tracking_flags ORDER BY name");

  $cache->{tracking_flags_names} = $tf_names;

  return @$tf_names;
}

sub page_before_template {
  my ($self, $args) = @_;
  my $page = $args->{'page_id'};
  my $vars = $args->{'vars'};

  if ($page eq 'tracking_flags_admin_list.html') {
    Bugzilla->user->in_group('admin')
      || ThrowUserError('auth_failure',
      {group => 'admin', action => 'access', object => 'administrative_pages'});
    admin_list($vars);

  }
  elsif ($page eq 'tracking_flags_admin_edit.html') {
    Bugzilla->user->in_group('admin')
      || ThrowUserError('auth_failure',
      {group => 'admin', action => 'access', object => 'administrative_pages'});
    admin_edit($vars);
  }
}

sub template_before_process {
  my ($self, $args) = @_;
  my $file = $args->{'file'};
  my $vars = $args->{'vars'};

  if ($file eq 'bug/create/create.html.tmpl') {
    my $flags
      = Bugzilla::Extension::TrackingFlags::Flag->match({
      product => $vars->{'product'}->name, enter_bug => 1, is_active => 1,
      });

    $vars->{tracking_flags}      = $flags;
    $vars->{tracking_flags_json} = _flags_to_json($flags);
    $vars->{tracking_flag_types} = FLAG_TYPES;
    $vars->{tracking_flag_components}
      = _flags_to_components($flags, $vars->{product});
    $vars->{highest_status_firefox} = _get_highest_status_firefox($flags);
  }
  elsif ($file eq 'bug/edit.html.tmpl'
    || $file eq 'bug/show.xml.tmpl'
    || $file eq 'email/bugmail.html.tmpl'
    || $file eq 'email/bugmail.txt.tmpl')
  {
    # note: bug/edit.html.tmpl doesn't support multiple bugs
    my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};

    if ($bug && !$bug->{error}) {
      my $flags = Bugzilla::Extension::TrackingFlags::Flag->match({
        product   => $bug->product,
        component => $bug->component,
        bug_id    => $bug->id,
        is_active => 1,
      });

      $vars->{tracking_flags}      = $flags;
      $vars->{tracking_flags_json} = _flags_to_json($flags);
    }

    $vars->{'tracking_flag_types'} = FLAG_TYPES;
  }
  elsif ($file eq 'list/edit-multiple.html.tmpl' && $vars->{'one_product'}) {
    $vars->{'tracking_flags'}
      = Bugzilla::Extension::TrackingFlags::Flag->match({
      product => $vars->{'one_product'}->name, is_active => 1
      });
  }
}

sub _flags_to_json {
  my ($flags) = @_;

  my $json = {flags => {}, types => [], comments => {},};

  my %type_map = map { $_->{name} => $_ } @{FLAG_TYPES()};
  foreach my $flag (@$flags) {
    my $flag_type = $flag->flag_type;

    $json->{flags}->{$flag_type}->{$flag->name} = $flag->bug_flag->value;

    if ($type_map{$flag_type}->{collapsed} && !grep { $_ eq $flag_type }
      @{$json->{types}})
    {
      push @{$json->{types}}, $flag_type;
    }

    foreach my $value (@{$flag->values}) {
      if (defined($value->comment) && $value->comment ne '') {
        $json->{comments}->{$flag->name}->{$value->value} = $value->comment;
      }
    }
  }

  return encode_json($json);
}

sub _flags_to_components {
  my ($flags, $product) = @_;

  # for each component, generate a list of visible tracking flags
  my $json = {};
  foreach my $component (@{$product->components}) {
    next unless $component->is_active;
    foreach my $flag (@$flags) {
      foreach my $visibility (@{$flag->visibility}) {
        if ($visibility->product_id == $product->id
          && (!$visibility->component_id || $visibility->component_id == $component->id))
        {
          $json->{$component->name} //= [];
          push @{$json->{$component->name}}, $flag->name;
        }
      }
    }
  }
  return encode_json($json);
}

sub _get_highest_status_firefox {
  my ($flags) = @_;

  my @status_flags
    = sort { $b <=> $a }
    map { $_->name =~ /(\d+)$/; $1 }
    grep { $_->is_active && $_->name =~ /^cf_status_firefox\d/ } @$flags;
  return @status_flags ? $status_flags[0] : undef;
}

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{'schema'}->{'tracking_flags'} = {
    FIELDS => [
      id       => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      field_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      name        => {TYPE => 'varchar(64)', NOTNULL => 1,},
      description => {TYPE => 'varchar(64)', NOTNULL => 1,},
      type        => {TYPE => 'varchar(64)', NOTNULL => 1,},
      sortkey     => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => '0',},
      enter_bug   => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE',},
      is_active   => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE',},
    ],
    INDEXES => [tracking_flags_idx => {FIELDS => ['name'], TYPE => 'UNIQUE',},],
  };
  $args->{'schema'}->{'tracking_flags_values'} = {
    FIELDS => [
      id               => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      tracking_flag_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'tracking_flags', COLUMN => 'id', DELETE => 'CASCADE',},
      },
      setter_group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'SET NULL',},
      },
      value     => {TYPE => 'varchar(64)', NOTNULL => 1,},
      sortkey   => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => '0',},
      enter_bug => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE',},
      is_active => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE',},
      comment   => {TYPE => 'TEXT',        NOTNULL => 0,},
    ],
    INDEXES => [
      tracking_flags_values_idx =>
        {FIELDS => ['tracking_flag_id', 'value'], TYPE => 'UNIQUE',},
    ],
  };
  $args->{'schema'}->{'tracking_flags_bugs'} = {
    FIELDS => [
      id               => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      tracking_flag_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'tracking_flags', COLUMN => 'id', DELETE => 'CASCADE',},
      },
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE',},
      },
      value => {TYPE => 'varchar(64)', NOTNULL => 1,},
    ],
    INDEXES => [
      tracking_flags_bugs_idx =>
        {FIELDS => ['tracking_flag_id', 'bug_id'], TYPE => 'UNIQUE',},
    ],
  };
  $args->{'schema'}->{'tracking_flags_visibility'} = {
    FIELDS => [
      id               => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      tracking_flag_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'tracking_flags', COLUMN => 'id', DELETE => 'CASCADE',},
      },
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE',},
      },
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE',},
      },
    ],
    INDEXES => [
      tracking_flags_visibility_idx => {
        FIELDS => ['tracking_flag_id', 'product_id', 'component_id'],
        TYPE   => 'UNIQUE',
      },
    ],
  };
}

sub install_update_db {
  my $dbh = Bugzilla->dbh;

  my $fk = $dbh->bz_fk_info('tracking_flags', 'field_id');
  if ($fk and !defined $fk->{DELETE}) {
    $fk->{DELETE} = 'CASCADE';
    $dbh->bz_alter_fk('tracking_flags', 'field_id', $fk);
  }

  $dbh->bz_add_column('tracking_flags', 'enter_bug',
    {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'TRUE',});
  $dbh->bz_add_column('tracking_flags_values', 'comment',
    {TYPE => 'TEXT', NOTNULL => 0,},
  );
}

sub install_filesystem {
  my ($self, $args) = @_;
  my $files          = $args->{files};
  my $extensions_dir = bz_locations()->{extensionsdir};
  $files->{"$extensions_dir/TrackingFlags/bin/bulk_flag_clear.pl"}
    = {perms => Bugzilla::Install::Filesystem::OWNER_EXECUTE};
}

sub active_custom_fields {
  my ($self, $args) = @_;
  my $wants     = $args->{'wants'};
  my $fields    = $args->{'fields'};
  my $params    = $args->{'params'};
  my $product   = $params->{'product'};
  my $component = $params->{'component'};

  return if $params->{skip_extensions};
  if ($wants && $wants->is_specific) {
    return if none { $wants->include->{$_} } Bugzilla->tracking_flag_names;
  }

  # Create a hash of current fields based on field names
  my %field_hash = map { $_->name => $_ } @$$fields;

  my @tracking_flags;
  if ($product) {
    $params->{'product_id'}   = $product->id;
    $params->{'component_id'} = $component->id if $component;
    $params->{'is_active'}    = 1;
    @tracking_flags = @{Bugzilla::Extension::TrackingFlags::Flag->match($params)};
  }
  else {
    @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  }

  # Add tracking flags to fields hash replacing if already exists for our
  # flag object instead of the usual Field.pm object
  foreach my $flag (@tracking_flags) {
    $field_hash{$flag->name} = $flag;
  }

  @$$fields = sort { $a->sortkey <=> $b->sortkey } values %field_hash;
}

sub buglist_columns {
  my ($self, $args) = @_;
  my $columns        = $args->{columns};
  my $dbh            = Bugzilla->dbh;
  my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  foreach my $flag (@tracking_flags) {
    $columns->{$flag->name} = {
      name  => "COALESCE(map_" . $flag->name . ".value, '---')",
      title => $flag->description
    };
  }

  # Allow other extensions to alter columns
  Bugzilla::Hook::process('tf_buglist_columns', {columns => $columns});
}

sub buglist_column_joins {
  my ($self, $args) = @_;

  # if there are elements in the tracking_flags array, then they have been
  # removed from the query, so we mustn't generate joins
  return if scalar @{$args->{search}->{tracking_flags} || []};

  my $column_joins   = $args->{'column_joins'};
  my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  foreach my $flag (@tracking_flags) {
    $column_joins->{$flag->name} = {
      as    => 'map_' . $flag->name,
      table => 'tracking_flags_bugs',
      extra => ['map_' . $flag->name . '.tracking_flag_id = ' . $flag->flag_id]
    };
  }

  # Allow other extensions to alter column_joins
  Bugzilla::Hook::process('tf_buglist_column_joins',
    {column_joins => $column_joins});
}

sub bug_create_cf_accessors {
  my ($self, $args) = @_;

  # Create the custom accessors for the flag values
  my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  foreach my $flag (@tracking_flags) {
    my $flag_name = $flag->name;
    if (!Bugzilla::Bug->can($flag_name)) {
      my $accessor = sub {
        my $self = shift;
        return $self->{$flag_name} if defined $self->{$flag_name};
        if (!exists $self->{'_tf_bug_values_preloaded'}) {

          # preload all values currently set for this bug
          my $bug_values
            = Bugzilla::Extension::TrackingFlags::Flag::Bug->match({bug_id => $self->id});
          foreach my $value (@$bug_values) {
            $self->{$value->tracking_flag->name} = $value->value;
          }
          $self->{'_tf_bug_values_preloaded'} = 1;
        }
        return $self->{$flag_name} ||= '---';
      };
      no strict 'refs';
      *{"Bugzilla::Bug::$flag_name"} = $accessor;
    }
    if (!Bugzilla::Bug->can("set_$flag_name")) {
      my $setter = sub {
        my ($self, $value) = @_;
        $value = ref($value) eq 'ARRAY' ? $value->[0] : $value;
        $self->set($flag_name, $value);
      };
      no strict 'refs';
      *{"Bugzilla::Bug::set_$flag_name"} = $setter;
    }
  }
}

sub search_operator_field_override {
  my ($self, $args) = @_;
  my $operators      = $args->{'operators'};
  my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  foreach my $flag (@tracking_flags) {
    $operators->{$flag->name} = {
      _non_changed => sub {
        _tracking_flags_search_nonchanged($flag->flag_id, @_);
      }
    };
  }

  # Allow other extensions to alter operators
  Bugzilla::Hook::process('tf_search_operator_field_override',
    {operators => $operators});
}

sub _tracking_flags_search_nonchanged {
  my ($flag_id, $search, $args) = @_;
  my ($bugs_table, $chart_id, $joins, $value, $operator)
    = @$args{qw(bugs_table chart_id joins value operator)};
  my $dbh = Bugzilla->dbh;

  return if ($operator =~ m/^changed/);

  my $bugs_alias  = "tracking_flags_bugs_$chart_id";
  my $flags_alias = "tracking_flags_$chart_id";

  my $bugs_join = {
    table => 'tracking_flags_bugs',
    as    => $bugs_alias,
    from  => $bugs_table . ".bug_id",
    to    => "bug_id",
    extra => [$bugs_alias . ".tracking_flag_id = $flag_id"]
  };

  push(@$joins, $bugs_join);

  if ($operator eq 'isempty' or $operator eq 'isnotempty') {
    $args->{'full_field'} = "$bugs_alias.value";
  }
  else {
    $args->{'full_field'} = "COALESCE($bugs_alias.value, '---')";
  }
}

sub request_cleanup {
  foreach my $flag (@FLAG_CACHE) {
    my $bug_flag = delete $flag->{bug_flag};
    if ($bug_flag) {
      delete $bug_flag->{bug};
      delete $bug_flag->{tracking_flag};
    }
    foreach my $value (@{$flag->{values}}) {
      delete $value->{tracking_flag};
    }
  }
  @FLAG_CACHE = ();
}

sub bug_end_of_create {
  my ($self, $args) = @_;
  my $bug       = $args->{'bug'};
  my $timestamp = $args->{'timestamp'};
  my $user      = Bugzilla->user;

  my $params = Bugzilla->request_cache->{tracking_flags_create_params};
  return if !$params;

  my $tracking_flags
    = Bugzilla::Extension::TrackingFlags::Flag->match({
    product => $bug->product, component => $bug->component, is_active => 1,
    });

  foreach my $flag (@$tracking_flags) {
    next if !$params->{$flag->name};
    foreach my $value (@{$flag->values}) {
      next if $value->value ne $params->{$flag->name};
      next if $value->value eq '---'; # do not insert if value is '---', same as empty
      if (!$flag->can_set_value($value->value)) {
        ThrowUserError('tracking_flags_change_denied',
          {flag => $flag, value => $value});
      }
      Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
        tracking_flag_id => $flag->flag_id,
        bug_id           => $bug->id,
        value            => $value->value,
      });

      # Add the name/value pair to the bug object
      $bug->{$flag->name} = $value->value;
    }
  }
}

sub object_end_of_set_all {
  my ($self, $args) = @_;
  my $object = $args->{object};
  my $params = $args->{params};

  return unless $object->isa('Bugzilla::Bug');

  # Do not filter by product/component as we may be changing those
  my $tracking_flags
    = Bugzilla::Extension::TrackingFlags::Flag->match({
    bug_id => $object->id, is_active => 1,
    });

  foreach my $flag (@$tracking_flags) {
    my $flag_name = $flag->name;
    if (exists $params->{$flag_name}) {
      my $value
        = ref($params->{$flag_name}) eq 'ARRAY'
        ? $params->{$flag_name}->[0]
        : $params->{$flag_name};
      $object->set($flag_name, $value);
    }
  }
}

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my ($bug, $field, $old_value, $new_value, $priv_results)
    = @$args{qw(bug field old_value new_value priv_results)};

  return if $field !~ /^cf_/ or $old_value eq $new_value;
  return
    unless my $flag
    = Bugzilla::Extension::TrackingFlags::Flag->new({name => $field});

  if ($flag->can_set_value($new_value)) {
    push @$priv_results, PRIVILEGES_REQUIRED_NONE;
  }
  else {
    push @$priv_results, PRIVILEGES_REQUIRED_EMPOWERED;
  }
}

sub bug_end_of_update {
  my ($self, $args) = @_;
  my ($bug, $old_bug, $timestamp, $changes)
    = @$args{qw(bug old_bug timestamp changes)};
  my $user = Bugzilla->user;

  # Do not filter by product/component as we may be changing those
  my $tracking_flags
    = Bugzilla::Extension::TrackingFlags::Flag->match({
    bug_id => $bug->id, is_active => 1,
    });

  my $product_id   = $bug->product_id;
  my $component_id = $bug->component_id;
  my $is_visible   = sub {
    $_->product_id == $product_id
      && (!$_->component_id || $_->component_id == $component_id);
  };

  my (@flag_changes);
  foreach my $flag (@$tracking_flags) {
    my $flag_name = $flag->name;
    my $new_value = $bug->$flag_name;
    my $old_value = $old_bug->$flag_name;

    if ($flag->bug_flag->id) {
      my $visibility = $flag->visibility;
      if (none { $is_visible->() } @$visibility) {
        push(@flag_changes, {flag => $flag, added => '---', removed => $new_value});
        next;
      }
    }

    if ($new_value ne $old_value) {

      # Do not allow if the user cannot set the old value or the new value
      if (!$flag->can_set_value($new_value)) {
        ThrowUserError('tracking_flags_change_denied',
          {flag => $flag, value => $new_value});
      }
      push(@flag_changes,
        {flag => $flag, added => $new_value, removed => $old_value});
    }
  }

  foreach my $change (@flag_changes) {
    my $flag    = $change->{'flag'};
    my $added   = $change->{'added'};
    my $removed = $change->{'removed'};

    if ($added eq '---') {
      $flag->bug_flag->remove_from_db();
    }
    elsif ($removed eq '---') {
      Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
        tracking_flag_id => $flag->flag_id, bug_id => $bug->id, value => $added,
      });
    }
    else {
      $flag->bug_flag->set_value($added);
      $flag->bug_flag->update($timestamp);
    }

    $changes->{$flag->name} = [$removed, $added];
    LogActivityEntry($bug->id, $flag->name, $removed, $added, $user->id,
      $timestamp);

    # Update the name/value pair in the bug object
    $bug->{$flag->name} = $added;
  }
}

sub bug_end_of_create_validators {
  my ($self, $args) = @_;
  my $params = $args->{params};

  # We need to stash away any params that are setting/updating tracking
  # flags early on. Otherwise set_all or insert_create_data will complain.
  my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
  my $cache = Bugzilla->request_cache->{tracking_flags_create_params} ||= {};
  foreach my $flag (@tracking_flags) {
    my $flag_name = $flag->name;
    if (defined $params->{$flag_name}) {
      $cache->{$flag_name} = delete $params->{$flag_name};
    }
  }
}

sub mailer_before_send {
  my ($self, $args) = @_;
  my $email = $args->{email};

  # Add X-Bugzilla-Tracking header or add to it
  # if already exists
  if ($email->header('X-Bugzilla-ID')) {
    my $bug_id = $email->header('X-Bugzilla-ID');

    my $tracking_flags
      = Bugzilla::Extension::TrackingFlags::Flag->match({bug_id => $bug_id});

    my @set_values = ();
    foreach my $flag (@$tracking_flags) {
      next if $flag->bug_flag->value eq '---';
      push(@set_values, $flag->description . ":" . $flag->bug_flag->value);
    }

    if (@set_values) {
      my $set_values_string = join(' ', @set_values);
      if ($email->header('X-Bugzilla-Tracking')) {
        $set_values_string
          = $email->header('X-Bugzilla-Tracking') . " " . $set_values_string;
      }
      $email->header_set('X-Bugzilla-Tracking' => $set_values_string);
    }
  }
}

# Purpose: generically handle generating pretty blocking/status "flags" from
# custom field names.
sub quicksearch_map {
  my ($self, $args) = @_;
  my $map = $args->{'map'};

  foreach my $name (keys %$map) {
    if ($name =~ /^cf_(blocking|tracking|status)_([a-z]+)?(\d+)?$/) {
      my $type    = $1;
      my $product = $2;
      my $version = $3;

      if ($version) {
        $version = join('.', split(//, $version));
      }

      my $pretty_name = $type;
      if ($product) {
        $pretty_name .= "-" . $product;
      }
      if ($version) {
        $pretty_name .= $version;
      }

      $map->{$pretty_name} = $name;
    }
  }
}

sub reorg_move_component {
  my ($self, $args) = @_;
  my $new_product = $args->{new_product};
  my $component   = $args->{component};

  Bugzilla->dbh->do(
    "UPDATE tracking_flags_visibility SET product_id=? WHERE component_id=?",
    undef, $new_product->id, $component->id,);
}

sub sanitycheck_check {
  my ($self, $args) = @_;
  my $status = $args->{status};

  $status->('tracking_flags_check');

  my ($count) = Bugzilla->dbh->selectrow_array("
        SELECT COUNT(*)
          FROM tracking_flags_visibility
         INNER JOIN components ON components.id = tracking_flags_visibility.component_id
         WHERE tracking_flags_visibility.product_id <> components.product_id
    ");
  if ($count) {
    $status->('tracking_flags_alert', undef, 'alert');
    $status->('tracking_flags_repair');
  }
}

sub sanitycheck_repair {
  my ($self, $args) = @_;
  return unless Bugzilla->cgi->param('tracking_flags_repair');

  my $status = $args->{'status'};
  my $dbh    = Bugzilla->dbh;
  $status->('tracking_flags_repairing');

  my $rows = $dbh->selectall_arrayref("
        SELECT DISTINCT tracking_flags_visibility.product_id AS bad_product_id,
               components.product_id AS good_product_id,
               tracking_flags_visibility.component_id
          FROM tracking_flags_visibility
         INNER JOIN components ON components.id = tracking_flags_visibility.component_id
         WHERE tracking_flags_visibility.product_id <> components.product_id
        ", {Slice => {}});
  foreach my $row (@$rows) {
    $dbh->do("
            UPDATE tracking_flags_visibility
               SET product_id=?
             WHERE product_id=? AND component_id=?
            ", undef, $row->{good_product_id}, $row->{bad_product_id},
      $row->{component_id},);
  }
}

__PACKAGE__->NAME;
