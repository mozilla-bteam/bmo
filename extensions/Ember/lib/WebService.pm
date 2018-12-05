# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Ember::WebService;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::WebService
  Bugzilla::WebService::Bug
  Bugzilla::WebService::Product);

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Product;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::Ember::FakeBug;

use Scalar::Util qw(blessed);
use Storable qw(dclone);

use constant PUBLIC_METHODS => qw(
  bug
  create
  get_attachments
  search
  show
);

use constant DATE_FIELDS => {show => ['last_updated'],};

use constant FIELD_TYPE_MAP => {
  0  => 'unknown',
  1  => 'freetext',
  2  => 'single_select',
  3  => 'multiple_select',
  4  => 'textarea',
  5  => 'datetime',
  6  => 'date',
  7  => 'bug_id',
  8  => 'bug_urls',
  9  => 'keywords',
  99 => 'extension'
};

use constant NON_EDIT_FIELDS => qw(
  assignee_accessible
  bug_group
  bug_id
  commenter
  cclist_accessible
  content
  creation_ts
  days_elapsed
  everconfirmed
  qacontact_accessible
  reporter
  reporter_accessible
  restrict_comments
  tag
  votes
);

use constant BUG_CHOICE_FIELDS => qw(
  bug_status
  component
  product
  resolution
  target_milestone
  version
);

use constant DEFAULT_VALUE_MAP => {
  op_sys       => 'defaultopsys',
  rep_platform => 'defaultplatform',
  priority     => 'defaultpriority',
  bug_severity => 'defaultseverity'
};

sub API_NAMES {

  # Internal field names converted to the API equivalents
  my %api_names = reverse %{Bugzilla::Bug::FIELD_MAP()};
  return \%api_names;
}

###############
# API Methods #
###############

sub create {
  my ($self, $params) = @_;

  Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->switch_to_shadow_db();

  my $product = delete $params->{product};
  $product
    || ThrowCodeError('params_required',
    {function => 'Ember.create', params => ['product']});

  my $product_obj = Bugzilla::Product->check($product);

  my $fake_bug = Bugzilla::Extension::Ember::FakeBug->new(
    {product_obj => $product_obj, reporter_id => Bugzilla->user->id});

  my @fields = $self->_get_fields($fake_bug);

  return {fields => \@fields};
}

sub show {
  my ($self, $params) = @_;
  my (@fields, $attachments, $comments, $data);
  my $dbh  = Bugzilla->dbh;
  my $user = Bugzilla->user;

  Bugzilla->switch_to_shadow_db();

  # Throw error if token was provided and user is not logged
  # in meaning token was invalid/expired.
  if (exists $params->{token} && !$user->id) {
    ThrowUserError('invalid_token');
  }

  my $bug_id = delete $params->{id};
  $bug_id
    || ThrowCodeError('params_required',
    {function => 'Ember.show', params => ['id']});

  my $bug = Bugzilla::Bug->check($bug_id);

  my $bug_hash = $self->_bug_to_hash($bug, $params);

  # Only return changes since last_updated if provided
  my $last_updated = delete $params->{last_updated};
  if ($last_updated) {
    trick_taint($last_updated);

    my $updated_fields = $dbh->selectcol_arrayref(
      'SELECT fieldid FROM bugs_activity
                                       WHERE bug_when > ? AND bug_id = ?', undef,
      ($last_updated, $bug->id)
    );

    if (@$updated_fields) {

      # Also add in the delta_ts value which is in the bugs_activity
      # entries
      push(@$updated_fields, get_field_id('delta_ts'));
      @fields = $self->_get_fields($bug, $updated_fields);
    }
  }

  # Return all the things
  else {
    @fields = $self->_get_fields($bug);
  }

  # Place the fields current value along with the field definition
  foreach my $field (@fields) {
    if (($field->{name} eq 'depends_on' || $field->{name} eq 'blocks')
      && scalar @{$bug_hash->{$field->{name}}})
    {
      my $bug_ids = delete $bug_hash->{$field->{name}};
      $user->visible_bugs($bug_ids);
      my $bug_objs = Bugzilla::Bug->new_from_list($bug_ids);

      my @new_list;
      foreach my $bug (@$bug_objs) {
        my $data;
        if ($user->can_see_bug($bug)) {
          $data
            = {id => $bug->id, status => $bug->bug_status, summary => $bug->short_desc};
        }
        else {
          $data = {id => $bug->id};
        }
        push(@new_list, $data);
      }
      $field->{current_value} = \@new_list;
    }
    else {
      $field->{current_value} = delete $bug_hash->{$field->{name}} || '';
    }
  }

  # Any left over bug values will be added to the field list
  # These are extra fields that do not have a corresponding
  # Field.pm object
  if (!$last_updated) {
    foreach my $key (keys %$bug_hash) {
      my $field = {name => $key, current_value => $bug_hash->{$key}};
      my $name = Bugzilla::Bug::FIELD_MAP()->{$key} || $key;
      $field->{can_edit} = $self->_can_change_field($name, $bug);
      push(@fields, $field);
    }
  }

  # Complete the return data
  my $data = {id => $bug->id, fields => \@fields};

  return $data;
}

sub search {
  my ($self, $params) = @_;

  my $total;
  if (exists $params->{offset} && exists $params->{limit}) {
    my $count_params = dclone($params);
    delete $count_params->{offset};
    delete $count_params->{limit};
    $count_params->{count_only} = 1;
    $total = $self->SUPER::search($count_params);
  }

  my $result = $self->SUPER::search($params);
  $result->{total} = defined $total ? $total : scalar(@{$result->{bugs}});
  return $result;
}

sub bug {
  my ($self, $params) = @_;
  my $dbh = Bugzilla->dbh;

  my $bug_id = delete $params->{id};
  $bug_id
    || ThrowCodeError('param_required', {function => 'Ember.bug', param => 'id'});

  my ($comments, $attachments) = ([], []);
  my $bug = $self->get({ids => [$bug_id]});
  $bug = $bug->{bugs}->[0];

  # Only return changes since last_updated if provided
  my $last_updated = delete $params->{last_updated};
  if ($last_updated) {
    trick_taint($last_updated);
    my $updated_fields = $dbh->selectcol_arrayref(
      'SELECT fielddefs.name
                                                         FROM fielddefs INNER JOIN bugs_activity
                                                              ON fielddefs.id = bugs_activity.fieldid
                                                        WHERE bugs_activity.bug_when > ?
                                                              AND bugs_activity.bug_id = ?',
      undef, ($last_updated, $bug->{id})
    );

    my %field_map = reverse %{Bugzilla::Bug::FIELD_MAP()};
    $field_map{'flagtypes.name'} = 'flags';

    my $changed_bug = {};
    foreach my $field (@$updated_fields) {
      my $field_name = $field_map{$field} || $field;
      if ($bug->{$field_name}) {
        $changed_bug->{$field_name} = $bug->{$field_name};
      }
    }
    $bug = $changed_bug;

    # Find any comments created since the last_updated date
    $comments = $self->comments({ids => $bug_id, new_since => $last_updated});

    # Find any new attachments or modified attachments since the
    # last_updated date
    my $updated_attachments = $dbh->selectcol_arrayref(
      'SELECT attach_id FROM attachments
                                       WHERE (creation_ts > ? OR modification_time > ?)
                                             AND bug_id = ?', undef,
      ($last_updated, $last_updated, $bug->{id})
    );
    if ($updated_attachments) {
      $attachments
        = $self->_get_attachments({
        attachment_ids => $updated_attachments, exclude_fields => ['data']
        });
    }
  }
  else {
    $comments = $self->comments({ids => [$bug_id]});
    $attachments
      = $self->_get_attachments({ids => [$bug_id], exclude_fields => ['data']});

  }

  $comments = $comments->{bugs}->{$bug_id}->{comments};

  return {bug => $bug, comments => $comments, attachments => $attachments,};
}

sub get_attachments {
  my ($self, $params) = @_;
  my $attachments = $self->_get_attachments($params);
  my $flag_types  = [];
  my $bug;
  if ($params->{ids}) {
    $bug = Bugzilla::Bug->check($params->{ids}->[0]);
    $flag_types = $self->_get_flag_types_bug($bug, 'attachment');
  }
  elsif ($params->{attachment_ids} && @$attachments) {
    $bug = Bugzilla::Bug->check($attachments->[0]->{bug_id});
    $flag_types = $self->_get_flag_types_all($bug, 'attachment')->{attachment};
  }
  if (@$flag_types) {
    @$flag_types = map { $self->_flagtype_to_hash($_, $bug) } @$flag_types;
  }
  return {attachments => $attachments, flag_types => $flag_types};
}

###################
# Private Methods #
###################

sub _get_attachments {
  my ($self, $params) = @_;
  my $user = Bugzilla->user;

  my $attachments = $self->attachments($params);

  if ($params->{ids}) {
    $attachments
      = [map { @{$attachments->{bugs}->{$_}} } keys %{$attachments->{bugs}}];
  }
  elsif ($params->{attachment_ids}) {
    $attachments = [map { $attachments->{attachments}->{$_} }
        keys %{$attachments->{attachments}}];
  }

  foreach my $attachment (@$attachments) {
    $attachment->{can_edit}
      = ($user->login eq $attachment->{creator} || $user->in_group('editbugs'))
      ? 1
      : 0;
  }

  return $attachments;
}

sub _get_fields {
  my ($self, $bug, $field_ids) = @_;
  my $user = Bugzilla->user;

  # Load the field objects we need
  my @field_objs;
  if ($field_ids) {

    # Load just the fields that match the ids provided
    @field_objs = @{Bugzilla::Field->match({id => $field_ids})};

  }
  else {
    # load up standard fields
    @field_objs = @{Bugzilla->fields({custom => 0})};

    # Load custom fields
    my $cf_params = {product => $bug->product_obj};
    $cf_params->{component} = $bug->component_obj if $bug->can('component_obj');
    $cf_params->{bug_id}    = $bug->id            if $bug->id;
    push(@field_objs, Bugzilla->active_custom_fields($cf_params));
  }

  my $return_groups = my $return_flags = $field_ids ? 0 : 1;
  my @fields;
  foreach my $field (@field_objs) {
    $return_groups = 1 if $field->name eq 'bug_group';
    $return_flags  = 1 if $field->name eq 'flagtypes.name';

    # Skip any special fields containing . in the name such as
    # for attachments.*, etc.
    next if $field->name =~ /\./;

    # Remove time tracking fields if the user is privileged
    next
      if (grep($field->name eq $_, TIMETRACKING_FIELDS)
      && !Bugzilla->user->is_timetracker);

    # These fields should never be set by the user
    next if grep($field->name eq $_, NON_EDIT_FIELDS);

    # We already selected a product so no need to display all choices
    # Might as well skip classification for new bugs as well.
    next
      if (!$bug->id
      && ($field->name eq 'product' || $field->name eq 'classification'));

    # Skip assigned_to and qa_contact for new bugs if user not in
    # editbugs group
    next
      if (!$bug->id
      && ($field->name eq 'assigned_to' || $field->name eq 'qa_contact')
      && !$user->in_group('editbugs', $bug->product_obj->id));

# Do not display obsolete fields or fields that should be displayed for create bug form
    next
      if (!$bug->id && $field->custom && ($field->obsolete || !$field->enter_bug));

    push(@fields, $self->_field_to_hash($field, $bug));
  }

  # Add group information as separate field
  if ($return_groups) {
    push(
      @fields,
      {
        description  => $self->type('string',  'Groups'),
        is_custom    => $self->type('boolean', 0),
        is_mandatory => $self->type('boolean', 0),
        name         => $self->type('string',  'groups'),
        values       => [
          map { $self->_group_to_hash($_, $bug) } @{$bug->product_obj->groups_available}
        ]
      }
    );
  }

  # Add flag information as separate field
  if ($return_flags) {
    my $flag_hash;
    if ($bug->id) {
      foreach my $flag_type ('bug', 'attachment') {
        $flag_hash->{$flag_type} = $self->_get_flag_types_bug($bug, $flag_type);
      }
    }
    else {
      $flag_hash = $self->_get_flag_types_all($bug);
    }
    my @flag_values;
    foreach my $flag_type ('bug', 'attachment') {
      foreach my $flag (@{$flag_hash->{$flag_type}}) {
        push(@flag_values, $self->_flagtype_to_hash($flag, $bug));
      }
    }

    push(
      @fields,
      {
        description  => $self->type('string',  'Flags'),
        is_custom    => $self->type('boolean', 0),
        is_mandatory => $self->type('boolean', 0),
        name         => $self->type('string',  'flags'),
        values       => \@flag_values
      }
    );
  }

  return @fields;
}

sub _get_flag_types_all {
  my ($self, $bug, $type) = @_;
  my $params = {is_active => 1};
  $params->{target_type} = $type if $type;
  return $bug->product_obj->flag_types($params);
}

sub _get_flag_types_bug {
  my ($self, $bug, $type) = @_;
  my $params = {
    target_type         => $type,
    product_id          => $bug->product_obj->id,
    component_id        => $bug->component_obj->id,
    bug_id              => $bug->id,
    active_or_has_flags => $bug->id,
  };
  return Bugzilla::Flag->_flag_types($params);
}

sub _group_to_hash {
  my ($self, $group, $bug) = @_;

  my $data = {
    description => $self->type('string', $group->description),
    name        => $self->type('string', $group->name)
  };

  if ($group->name eq $bug->product_obj->default_security_group) {
    $data->{security_default} = $self->type('boolean', 1);
  }

  return $data;
}

sub _field_to_hash {
  my ($self, $field, $bug) = @_;

  my $data = {
    is_custom    => $self->type('boolean', $field->custom),
    description  => $self->type('string',  $field->description),
    is_mandatory => $self->type('boolean', $field->is_mandatory),
  };

  if ($field->custom) {
    $data->{type} = $self->type('string', FIELD_TYPE_MAP->{$field->type});
  }

  # Use the API name if one is present instead of the internal field name
  my $field_name = $field->name;
  $field_name = API_NAMES->{$field_name} || $field_name;

  if ($field_name eq 'longdesc') {
    $field_name = $bug->id ? 'comment' : 'description';
  }

  $data->{name} = $self->type('string', $field_name);

  # Set can_edit true or false if we are editing a current bug
  if ($bug->id) {

    # 'delta_ts's can_edit is incorrectly set in fielddefs
    $data->{can_edit}
      = $field->name eq 'delta_ts'
      ? $self->type('boolean', 0)
      : $self->_can_change_field($field, $bug);
  }

  # description for creating a new bug, otherwise comment

  # FIXME 'version' and 'target_milestone' types are incorrectly set in fielddefs
  if ( $field->is_select
    || $field->name eq 'version'
    || $field->name eq 'target_milestone')
  {
    $data->{values} = [$self->_get_field_values($field, $bug)];
  }

  # Add default values for specific fields if new bug
  if (!$bug->id && DEFAULT_VALUE_MAP->{$field->name}) {
    my $default_value = Bugzilla->params->{DEFAULT_VALUE_MAP->{$field->name}};
    $data->{default_value} = $default_value;
  }

  return $data;
}

sub _value_to_hash {
  my ($self, $value, $bug) = @_;

  my $data = {name => $self->type('string', $value->name)};

  if ($bug->{bug_id}) {
    $data->{is_active} = $self->type('boolean', $value->is_active);
  }

  if ($value->can('sortkey')) {
    $data->{sort_key} = $self->type('int', $value->sortkey || 0);
  }

  if ($value->isa('Bugzilla::Component')) {
    $data->{default_assignee} = $self->_user_to_hash($value->default_assignee);
    $data->{initial_cc} = [map { $self->_user_to_hash($_) } @{$value->initial_cc}];
    if (Bugzilla->params->{useqacontact} && $value->default_qa_contact) {
      $data->{default_qa_contact} = $self->_user_to_hash($value->default_qa_contact);
    }
  }

  if ($value->can('description')) {
    $data->{description} = $self->type('string', $value->description);
  }

  return $data;
}

sub _user_to_hash {
  my ($self, $user) = @_;

  my $data = {real_name => $self->type('string', $user->name)};

  if (Bugzilla->user->id) {
    $data->{email} = $self->type('string', $user->email);
  }

  return $data;
}

sub _get_field_values {
  my ($self, $field, $bug) = @_;

  # Certain fields are special and should use $bug->choices
  # to determine editability and not $bug->check_can_change_field
  my @values;
  if (grep($field->name eq $_, BUG_CHOICE_FIELDS)) {
    @values = @{$bug->choices->{$field->name}};
  }
  else {
    # We need to get the values from the product for
    # component, version, and milestones.
    if ($field->name eq 'component') {
      @values = @{$bug->product_obj->components};
    }
    elsif ($field->name eq 'target_milestone') {
      @values = @{$bug->product_obj->milestones};
    }
    elsif ($field->name eq 'version') {
      @values = @{$bug->product_obj->versions};
    }
    else {
      @values = @{$field->legal_values};
    }
  }

  my @filtered_values;
  foreach my $value (@values) {
    next if !$bug->id && !$value->is_active;
    next if $bug->id && !$self->_can_change_field($field, $bug, $value->name);
    push(@filtered_values, $value);
  }

  return map { $self->_value_to_hash($_, $bug) } @filtered_values;
}

sub _can_change_field {
  my ($self, $field, $bug, $value) = @_;
  my $user = Bugzilla->user;
  my $field_name = blessed $field ? $field->name : $field;

  # Cannot set resolution on bug creation
  return $self->type('boolean', 0)
    if ($field_name eq 'resolution' && !$bug->{bug_id});

  # Cannot edit an obsolete or inactive custom field
  return $self->type('boolean', 0)
    if (blessed $field && $field->custom && $field->obsolete);

  # If not a multi-select or single-select, value is not provided
  # and we just check if the field itself is editable by the user.
  if (!defined $value) {
    return $self->type('boolean', $bug->check_can_change_field($field_name, 0, 1));
  }

  return $self->type('boolean',
    $bug->check_can_change_field($field_name, '', $value));
}

sub _flag_to_hash {
  my ($self, $flag) = @_;

  my $data = {
    id                => $self->type('int',      $flag->id),
    name              => $self->type('string',   $flag->name),
    type_id           => $self->type('int',      $flag->type_id),
    creation_date     => $self->type('dateTime', $flag->creation_date),
    modification_date => $self->type('dateTime', $flag->modification_date),
    status            => $self->type('string',   $flag->status)
  };

  foreach my $field (qw(setter requestee)) {
    my $field_id = $field . "_id";
    $data->{$field} = $self->_user_to_hash($flag->$field) if $flag->$field_id;
  }

  $data->{type} = $flag->attach_id ? 'attachment' : 'bug';
  $data->{attach_id} = $flag->attach_id if $flag->attach_id;

  return $data;
}

sub _flagtype_to_hash {
  my ($self, $flagtype, $bug) = @_;
  my $user = Bugzilla->user;

  my $cansetflag     = $user->can_set_flag($flagtype);
  my $canrequestflag = $user->can_request_flag($flagtype);

  my $data = {
    id               => $self->type('int',     $flagtype->id),
    name             => $self->type('string',  $flagtype->name),
    description      => $self->type('string',  $flagtype->description),
    type             => $self->type('string',  $flagtype->target_type),
    is_requestable   => $self->type('boolean', $flagtype->is_requestable),
    is_requesteeble  => $self->type('boolean', $flagtype->is_requesteeble),
    is_multiplicable => $self->type('boolean', $flagtype->is_multiplicable),
    can_set_flag     => $self->type('boolean', $cansetflag),
    can_request_flag => $self->type('boolean', $canrequestflag)
  };

  my @values;
  foreach my $value ('?', '+', '-') {
    push(@values, $self->type('string', $value));
  }
  $data->{values} = \@values;

  # if we're creating a bug, we need to return all valid flags for
  # this product, as well as inclusions & exclusions so ember can
  # display relevant flags once the component is selected
  if (!$bug->id) {
    my $inclusions = $self->_flagtype_clusions_to_hash($flagtype->inclusions,
      $bug->product_obj->id);
    my $exclusions = $self->_flagtype_clusions_to_hash($flagtype->exclusions,
      $bug->product_obj->id);

    # if we have both inclusions and exclusions, the exclusions are redundant
    $exclusions = [] if @$inclusions && @$exclusions;

    # no need to return anything if there's just "any component"
    $data->{inclusions} = $inclusions if @$inclusions && $inclusions->[0] ne '';
    $data->{exclusions} = $exclusions if @$exclusions && $exclusions->[0] ne '';
  }

  return $data;
}

sub _flagtype_clusions_to_hash {
  my ($self, $clusions, $product_id) = @_;
  my $result = [];
  foreach my $key (keys %$clusions) {
    my ($prod_id, $comp_id) = split(/:/, $clusions->{$key}, 2);
    if ($prod_id == 0 || $prod_id == $product_id) {
      if ($comp_id) {
        my $component = Bugzilla::Component->new({id => $comp_id, cache => 1});
        push @$result, $component->name;
      }
      else {
        return [''];
      }
    }
  }
  return $result;
}

sub rest_resources {
  return [
    # create page - single product name
    qr{^/ember/create/(.*)$},
    {
      GET => {
        method => 'create',
        params => sub {
          return {product => $_[0]};
        }
      }
    },

    # create page - one or more products
    qr{^/ember/create$},
    {GET => {method => 'create'}},

    # show bug page - single bug id
    qr{^/ember/show/(\d+)$},
    {
      GET => {
        method => 'show',
        params => sub {
          return {id => $_[0]};
        }
      }
    },

    # search - wrapper around SUPER::search which also includes the total
    # number of bugs when using pagination
    qr{^/ember/search$},
    {GET => {method => 'search',},},

    # get current bug attributes without field information - single bug id
    qr{^/ember/bug/(\d+)$},
    {
      GET => {
        method => 'bug',
        params => sub {
          return {id => $_[0]};
        }
      }
    },

    # attachments - wrapper around SUPER::attachments that also includes
    # can_edit attribute
    qr{^/ember/bug/(\d+)/attachments$},
    {
      GET => {
        method => 'get_attachments',
        params => sub {
          return {ids => $_[0]};
        }
      }
    },
    qr{^/ember/bug/attachments/(\d+)$},
    {
      GET => {
        method => 'get_attachments',
        params => sub {
          return {attachment_ids => $_[0]};
        }
      }
    }
  ];
}

1;

__END__

=head1 NAME

Bugzilla::Extension::Ember::Webservice - The BMO Ember WebServices API

=head1 DESCRIPTION

This module contains API methods that are useful to user's of the Bugzilla Ember
based UI.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

=head2 create

B<UNSTABLE>

=over

=item B<Description>

This method returns the necessary information for the Bugzilla Ember UI to generate a
bug creation page.

=item B<Params>

You pass a field called C<product> that must be a valid Bugzilla product name.

=over

=item C<product> (string) - The Bugzilla product name.

=back

=item B<Returns>

=over

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.2>.

=back

=back

=head2 show

B<UNSTABLE>

=over

=item B<Description>

This method returns the necessary information for the Bugzilla Ember UI to properly
generate a page to edit current bugs.

=item B<Params>

You pass a field called C<id> that is the current bug id.

=over

=item C<id> (int) - A bug id.

=back

=item B<Returns>

=over

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.0>.

=back

=back

=head2 search

B<UNSTABLE>

=over

=item B<Description>

A wrapper around Bugzilla's C<search> method which also returns the total of
bugs matching a query, even if the limit and offset parameters are supplied.

=item B<Params>

As per Bugzilla::WebService::Bug::search()

=item B<Returns>

=over

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=back

=back

=head2 bug

B<UNSTABLE>

=over

=item B<Description>

This method returns just the current bug values, comments, and attachments without
all of the field information.

=item B<Params>

You pass a field called C<id> that is a valid bug ids.

=over

=item C<id> (integer) - A valid bug id

=item C<last_updated> - (dateTime) An optional timestamp that includes only fields,
attachments, or comments that have been changed or added since.

=back

=item B<Returns>

=over

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.2>.

=back

=back

=head2 get_attachments

B<UNSTABLE>

=over

=item B<Description>

This method returns the current attachment data and flag types for a given
bug id or attachment id.

=item B<Params>

You pass a field called C<id> that is a valid bug id or an C<attachment_id> which
is a valid attachment id.

=over

=item C<id> (integer) - A valid bug id.

=item C<attachment_id> (integer) - A valid attachment id.

=back

=item B<Returns>

=over

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.2>.

=back

=back
