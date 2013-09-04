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
use Bugzilla::Product;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::Ember::FakeBug;

use Scalar::Util qw(blessed);
use Data::Dumper;

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
    bug_id
    commenter
    cclist_accessible
    content
    creation_ts
    days_elapsed
    delta_ts
    everconfirmed
    qacontact_accessible
    reporter
    reporter_accessible
    restrict_comments
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

###############
# API Methods #
###############

sub create {
    my ($self, $params) = @_;

    Bugzilla->switch_to_shadow_db();

    my $product = delete $params->{product};
    $product || ThrowCodeError('params_required',
                               { function => 'Ember.create', params => ['product'] });

    my $product_obj = Bugzilla::Product->check($product);

    my $fake_bug = Bugzilla::Extension::Ember::FakeBug->new({ product_obj => $product_obj });

    my @fields = $self->_get_fields($fake_bug);

    return {
        fields => \@fields
    };
}

sub show {
    my ($self, $params) = @_;
    my (@fields, $attachments, $comments, $data);
    my $dbh = Bugzilla->dbh;

    Bugzilla->switch_to_shadow_db();

    my $bug_id = delete $params->{id};
    $bug_id || ThrowCodeError('params_required',
                              { function => 'Ember.show', params => ['id'] });

    my $bug = Bugzilla::Bug->check($bug_id);

    my $bug_hash = $self->_bug_to_hash($bug, $params);

    # Only return changes since last_updated if provided
    my $last_updated = delete $params->{last_updated};
    if ($last_updated) {
        trick_taint($last_updated);

        my $updated_fields =
            $dbh->selectcol_arrayref('SELECT fieldid FROM bugs_activity
                                       WHERE bug_when > ? AND bug_id = ?',
                                     undef, ($last_updated, $bug->id));
        if ($updated_fields) {
            # Also add in the delta_ts value which is in the
            # bugs_activity entries
            push(@$updated_fields, get_field_id('delta_ts'));
            @fields = $self->_get_fields($bug, $updated_fields);
        }

        # Find any comments created since the last_updated date
        $comments = $self->comments({ ids => $bug_id, new_since => $last_updated });
        $comments = $comments->{bugs}->{$bug_id}->{comments} || undef;

        # Find any new attachments or modified attachments since the
        # last_updated date
        my $updated_attachments =
            $dbh->selectcol_arrayref('SELECT attach_id FROM attachments
                                       WHERE (creation_ts > ? OR modification_time > ?)
                                             AND bug_id = ?',
                                     undef, ($last_updated, $last_updated, $bug->id));
        if ($updated_attachments) {
            $attachments = $self->attachments({ attachment_ids => $updated_attachments,
                                                exclude_fields => ['data'] });
            $attachments = [ map { $attachments->{attachments}->{$_} }
                             keys %{ $attachments->{attachments} } ];
        }
    }
    # Return all the things
    else {
        @fields = $self->_get_fields($bug);
        $comments = $self->comments({ ids => $bug_id });
        $comments = $comments->{bugs}->{$bug_id}->{comments} || undef;
        $attachments = $self->attachments({ ids => $bug_id,
                                            exclude_fields => ['data'] });
        $attachments = $attachments->{bugs}->{$bug_id} || undef;

    }

    # Place the fields current value along with the field definition
    foreach my $field (@fields) {
        $field->{current_value} = delete $bug_hash->{$field->{api_name}}
                                  // delete $bug_hash->{$field->{name}}
                                  // '';
    }

    # Any left over bug values will be added to the field list
    # These are extra fields that do not have a corresponding
    # Field.pm object
    if (!$last_updated) {
        foreach my $key (keys %$bug_hash) {
            my $field = {
                name          => $key,
                api_name      => $key,
                current_value => $bug_hash->{$key}
            };
            push(@fields, $field);
        }
    }

    # Complete the return data
    my $data = { id => $bug->id, fields => \@fields };

    # Add the comments
    $data->{comments} = $comments if $comments;

    # Add the attachments
    $data->{attachments} = $attachments if $attachments;

    return $data;
}

###################
# Private Methods #
###################

sub _get_fields {
    my ($self, $bug, $field_ids) = @_;
    my $new_bug = $bug->{bug_id} ? 0 : 1;

    # Load the field objects we need
    my @field_objs;
    if ($field_ids) {
        # Load just the fields that match the ids provided
        @field_objs = @{ Bugzilla::Field->match({ id => $field_ids }) };

    }
    else {
        # load up standard fields
        @field_objs = @{ Bugzilla->fields({ custom => 0 }) };

        # Load custom fields
        my $cf_params = { product => $bug->{product_obj} };
        $cf_params->{component} = $bug->{component_obj} if $bug->{component_obj};
        $cf_params->{bug_id} = $bug->{bug_id} if !$new_bug;
        push(@field_objs, Bugzilla->active_custom_fields($cf_params));
    }

    # Internal field names converted to the API equivalents
    my %api_names = reverse %{ Bugzilla::Bug::FIELD_MAP() };

    my @fields;
    foreach my $field_obj (@field_objs) {
        my $field_name = $field_obj->name;

        # Skip any special fields containing . in the name such as
        # for attachments.*, etc.
        next if $field_name =~ /\./;

        # Remove time tracking fields if the user is privileged
        next if ($field_name =~ /_time$/ && !Bugzilla->user->is_timetracker);

        # These fields should never be set by the user
        next if grep($field_name eq $_, NON_EDIT_FIELDS);

        # We already selected a product so no need to display all choices
        next if ($new_bug && $field_name eq 'product');

        # Do not display obsolete fields or fields that should be displayed for create bug form
        next if ($new_bug && $field_obj->custom
                 && ($field_obj->obsolete || !$field_obj->enter_bug));

        my $field_hash = $self->_field_to_hash($field_obj);

        $field_hash->{api_name} = $api_names{$field_name} || $field_name;

        if (!$new_bug) {
            $field_hash->{can_edit} = $self->_can_change_field($field_obj, $bug);
        }
        else {
            next if !$self->_can_change_field($field_obj, $bug);
        }

        # FIXME 'version' and 'target_milestone' types are incorrectly set in fielddefs
        if ($field_obj->is_select
            || $field_obj->name eq 'version'
            || $field_obj->name eq 'target_milestone')
        {
            $field_hash->{values} = [ $self->_get_field_values($field_obj, $bug) ];
        }

        # Add default values for specific fields if new bug
        if ($new_bug && DEFAULT_VALUE_MAP->{$field_obj->name}) {
            my $default_value = Bugzilla->params->{DEFAULT_VALUE_MAP->{$field_obj->name}};
            $field_hash->{default_value} = $default_value;
        }

        push(@fields, $field_hash);
    }


    return @fields;
}

sub _field_to_hash {
    my ($self, $field) = @_;

    my $data = {
        is_custom    => $self->type('boolean', $field->custom),
        name         => $self->type('string', $field->name),
        description  => $self->type('string', $field->description),
        is_mandatory => $self->type('boolean', $field->is_mandatory),
    };

    if ($field->custom) {
        $data->{type} = $self->type('string', FIELD_TYPE_MAP->{$field->type});
    }

    return $data;
}

sub _value_to_hash {
    my ($self, $value) = @_;

    my $data = {
        name => $self->type('string', $value->name)
    };

    if ($value->can('sortkey')) {
        $data->{sort_key} = $self->type('int', $value->sortkey || 0);
    }

    if ($value->isa('Bugzilla::Component')) {
        $data->{default_assignee} = $self->_user_to_hash($value->default_assignee);
        $data->{initial_cc} = [ map { $self->_user_to_hash($_) } @{ $value->initial_cc } ];
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

    my $data = {
        real_name =>  $self->type('string', $user->name)
    };

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
        @values = @{ $bug->choices->{$field->name} };
    }
    else {
        # We need to get the values from the product_obj for
        # component, version, and milestones.
        if ($field->name eq 'component') {
            @values = @{ $bug->{product_obj}->components };
        }
        elsif ($field->name eq 'target_milestone') {
            @values = @{ $bug->{product_obj}->milestones };
        }
        elsif ($field->name eq 'version') {
            @values = @{ $bug->{product_obj}->versions };
        }
        else {
            @values = @{ $field->legal_values };
        }
    }

    my @filtered_values;
    foreach my $value (@values) {
        next if !$value->is_active;
        next if !$self->_can_change_field($field, $bug, $value->{name});
        push(@filtered_values, $value);
    }

    return map { $self->_value_to_hash($_) } @filtered_values;
}

sub _can_change_field {
    my ($self, $field, $bug, $value) = @_;
    my $user = Bugzilla->user;

    # Cannot set resolution on bug creation
    return $self->type('boolean', 0) if $field->{name} eq 'resolution' && !$bug->{bug_id};

    # Cannot edit an obsolete or inactive custom field
    return $self->type('boolean', 0) if ($field->{is_custom} && $field->{is_obsolete});

    # If not a multi-select or single-select, value is not provided
    # and we just check if the field itself is editable by the user.
    if (!defined $value) {
        return $self->type('boolean', $bug->check_can_change_field($field->{name}, 1, 0));
    }

    return $self->type('boolean', $bug->check_can_change_field($field->{name}, '', $value));
}

sub rest_resources {
    return [
        # create page - single product name
        qr{^/ember/create/(.*)$}, {
            GET => {
                method => 'create',
                params => sub {
                    return { product => $_[0] };
                }
            }
        },
        # create page - one or more products
        qr{^/ember/create$}, {
            GET => {
                method => 'create'
            }
        },
        # show bug page - single bug id
        qr{^/ember/show/(\d+)$}, {
            GET => {
                method => 'show',
                params => sub {
                    return { id => $_[0] };
                }
            }
        },
        # show bug page - one or more bug ids
        qr{^/ember/show$}, {
            GET => {
                method => 'show'
            }
        }
    ];
};

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
