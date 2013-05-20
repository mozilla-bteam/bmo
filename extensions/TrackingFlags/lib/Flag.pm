# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Flag;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Util qw(detaint_natural);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::Extension::TrackingFlags::Flag::Value;
use Bugzilla::Extension::TrackingFlags::Flag::Visibility;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'tracking_flags';

use constant DB_COLUMNS => qw(
    id
    field_id
    name
    description
    type
    sortkey
    is_active
);

use constant LIST_ORDER => 'sortkey';

use constant UPDATE_COLUMNS => qw(
    name
    description
    type
    sortkey
    is_active
);

use constant VALIDATORS => {
    name        => \&_check_name,
    description => \&_check_description,
    type        => \&_check_type,
    sortkey     => \&_check_sortkey,
    is_active   => \&Bugzilla::Object::check_boolean,

};

use constant UPDATE_VALIDATORS => {
    name        => \&_check_name,
    description => \&_check_description,
    type        => \&_check_type,
    sortkey     => \&_check_sortkey,
    is_active   => \&Bugzilla::Object::check_boolean,
};

###############################
####      Methods          ####
###############################

sub create {
    my $class = shift;
    my $params = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $params = $class->run_create_validators($params);

    # We ihave to create an entry for this new flag
    # in the fielddefs table for use elsewhere. We cannot
    # use Bugzilla::Field->create as it will create the
    # additional tables needed by custom fields which we
    # do not need. Also we do this so as not to add a
    # another column to the bugs table.
    # We will create the entry as a custom field with a
    # type of FIELD_TYPE_EXTENSION so Bugzilla will skip
    # these field types in certain parts of the core code.
    $dbh->do("INSERT INTO fielddefs
             (name, description, sortkey, type, custom, obsolete, buglist)
              VALUES
             (?, ?, ?, ?, ?, ?, ?)",
             undef,
             $params->{'name'},
             $params->{'description'},
             $params->{'sortkey'},
             FIELD_TYPE_EXTENSION,
             1, 0, 1);
    $params->{'field_id'} = $dbh->bz_last_key;

    my $flag = $class->SUPER::create($params);

   $dbh->bz_commit_transaction();

    return $flag;
}

sub update {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    my $old_self = $self->new($self->flag_id);

    # HACK! Bugzilla::Object::update uses hardcoded $self->id
    # instead of $self->{ID_FIELD} so we need to reverse field_id
    # and the real id temporarily
    my $field_id = $self->id;
    $self->{'field_id'} = $self->{'id'};

    my $changes = $self->SUPER::update(@_);

    $self->{'field_id'} = $field_id;

    # Update the fielddefs entry
    $dbh->do("UPDATE fielddefs SET name = ?, description = ? WHERE name = ?",
             undef,
             $self->id, $self->description, $old_self->name);

    return $changes;
}

sub match {
    my $class = shift;
    my ($params) = @_;

    my $bug_id = delete $params->{'bug_id'};

    # Retrieve all existing flags for this bug if bug_id given
    my $bug_flags = [];
    if ($bug_id) {
        $bug_flags = Bugzilla::Extension::TrackingFlags::Flag::Bug->match({
            bug_id => $bug_id
        });
    }

    # Retrieve all flags relevant for the given product and component
    if ($params->{'component'} || $params->{'component_id'}
        || $params->{'product'} || $params->{'product_id'})
    {
        my $visible_flags
            = Bugzilla::Extension::TrackingFlags::Flag::Visibility->match(@_);
        my @flag_ids = map { $_->tracking_flag_id } @$visible_flags;

        delete $params->{'component'} if exists $params->{'component'};
        delete $params->{'component_id'} if exists $params->{'component_id'};
        delete $params->{'product'} if exists $params->{'product'};
        delete $params->{'product_id'} if exists $params->{'product_id'};

        $params->{'id'} = \@flag_ids;
    }

    my $flags = $class->SUPER::match(@_);

    my %flag_hash = map { $_->flag_id => $_ } @$flags;

    if (@$bug_flags) {
        map { $flag_hash{$_->tracking_flag->flag_id} = $_->tracking_flag } @$bug_flags;
    }

    # Prepopulate bug_flag if bug_id passed
    if ($bug_id) {
        foreach my $flag (keys %flag_hash) {
            $flag_hash{$flag}->bug_flag($bug_id);
        }
    }

    return [ values %flag_hash ];
}

sub get_all {
    my $self = shift;
    my $cache = Bugzilla->request_cache;
    $cache->{'tracking_flags_all'} ||= [ $self->SUPER::get_all(@_) ];
    return @{ $cache->{'tracking_flags_all'} };
}

sub remove_from_db {
    my $self = shift;
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();
    $dbh->do('DELETE FROM fielddefs WHERE name = ?', undef, $self->name);
    $self->SUPER::remove_from_db(@_);
    $dbh->bz_commit_transaction();
}

###############################
####      Validators       ####
###############################

sub _check_name {
    my ($invocant, $name) = @_;
    $name || ThrowCodeError('param_required', { param => 'name' });
    return $name;
}

sub _check_description {
    my ($invocant, $description) = @_;
    $description || ThrowCodeError( 'param_required', { param => 'description' } );
    return $description;
}

sub _check_type {
    my ($invocant, $type) = @_;
    $type || ThrowCodeError( 'param_required', { param => 'type' } );
    grep($_->{name} eq $type, @{FLAG_TYPES()})
        || ThrowUserError('tracking_flags_invalid_flag_type', { type => $type });
    return $type;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    detaint_natural($sortkey)
        || ThrowUserError('field_invalid_sortkey', { sortkey => $sortkey });
    return $sortkey;
}

###############################
####       Setters         ####
###############################

sub set_name        { $_[0]->set('name', $_[1]);        }
sub set_description { $_[0]->set('description', $_[1]); }
sub set_type        { $_[0]->set('type', $_[1]);        }
sub set_sortkey     { $_[0]->set('sortkey', $_[1]);     }
sub set_is_active   { $_[0]->set('is_active', $_[1]);   }

###############################
####      Accessors        ####
###############################

sub flag_id     { return $_[0]->{'id'};          }
sub name        { return $_[0]->{'name'};        }
sub description { return $_[0]->{'description'}; }
sub flag_type   { return $_[0]->{'type'};        }
sub sortkey     { return $_[0]->{'sortkey'};     }
sub is_active   { return $_[0]->{'is_active'};   }

sub values {
    my ($self) = @_;
    $self->{'values'} ||= Bugzilla::Extension::TrackingFlags::Flag::Value->match({
        tracking_flag_id => $self->flag_id
    });
    return $self->{'values'};
}

sub visibility {
    my ($self) = @_;
    $self->{'visibility'} ||= Bugzilla::Extension::TrackingFlags::Flag::Visibility->match({
        tracking_flag_id => $self->flag_id
    });
    return $self->{'visibility'};
}

sub can_set_value {
    my ($self, $new_value, $user) = @_;
    $user ||= Bugzilla->user;
    my $new_value_obj;
    foreach my $value (@{$self->values}) {
        $new_value_obj = $value if $value->value eq $new_value;
    }
    return $new_value_obj && $user->in_group($new_value_obj->setter_group->name)
           ? 1
           : 0;
}

sub bug_flag {
    my ($self, $bug_id) = @_;
    # Set to 0 if not defined so that the default empty value will be used (i.e. '---')
    $bug_id = defined $bug_id ? $bug_id : $self->{'bug_id'} || 0;
    $self->{'bug_id'} = $bug_id;
    $self->{'bug_flag'}
        ||= Bugzilla::Extension::TrackingFlags::Flag::Bug->new(
            { condition => "tracking_flag_id = ? AND bug_id = ?",
              values    => [ $self->flag_id, $bug_id ] });
    return $self->{'bug_flag'};
}

sub has_values {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return scalar $dbh->selectrow_array("
        SELECT 1
          FROM tracking_flags_bugs
         WHERE tracking_flag_id = ? " .
               $dbh->sql_limit(1),
        undef, $self->flag_id);
}

######################################
# Compatibility with Bugzilla::Field #
######################################

# Here we return 'field_id' instead of the real
# id as we want other Bugzilla code to treat this
# as a Bugzilla::Field object in certain places.
sub id                     { return $_[0]->{'field_id'};  }
sub type                   { return FIELD_TYPE_EXTENSION; }
sub legal_values           { return $_[0]->values;        }
sub custom                 { return 1;     }
sub in_new_bugmail         { return 1;     }
sub obsolete               { return 0;     }
sub enter_bug              { return 1;     }
sub buglist                { return 1;     }
sub is_select              { return 1;     }
sub is_abnormal            { return 1;     }
sub is_timetracking        { return 0;     }
sub visibility_field       { return undef; }
sub visibility_values      { return undef; }
sub controls_visibility_of { return undef; }
sub value_field            { return undef; }
sub controls_values_of     { return undef; }
sub is_visible_on_bug      { return 1;     }
sub is_relationship        { return 0;     }
sub reverse_desc           { return '';    }
sub is_mandatory           { return 0;     }
sub is_numeric             { return 0;     }

1;
