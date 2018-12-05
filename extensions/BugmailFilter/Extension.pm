# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla::BugMail;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BugmailFilter::Constants;
use Bugzilla::Extension::BugmailFilter::FakeField;
use Bugzilla::Extension::BugmailFilter::Filter;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw(template_var);
use Encode;
use List::MoreUtils qw(uniq);
use Sys::Syslog qw(:DEFAULT);

#
# preferences
#

sub user_preferences {
  my ($self, $args) = @_;
  return unless $args->{current_tab} eq 'bugmail_filter';

  if ($args->{save_changes}) {
    my $input = Bugzilla->input_params;

    if ($input->{add_filter}) {

      # add a new filter

      my $params = {user_id => Bugzilla->user->id,};
      $params->{field_name} = $input->{field} || IS_NULL;
      if ($params->{field_name} eq '~') {
        $params->{field_name} = '~' . $input->{field_contains};
      }
      $params->{relationship} = $input->{relationship} || IS_NULL;
      if ($input->{changer}) {
        Bugzilla::User::match_field({changer => {type => 'single'}});
        $params->{changer_id}
          = Bugzilla::User->check({name => $input->{changer}, cache => 1,})->id;
      }
      else {
        $params->{changer_id} = IS_NULL;
      }
      if (my $product_name = $input->{product}) {
        my $product = Bugzilla::Product->check({name => $product_name, cache => 1});
        $params->{product_id} = $product->id;

        if (my $component_name = $input->{component}) {
          $params->{component_id}
            = Bugzilla::Component->check({
            name => $component_name, product => $product, cache => 1
            })->id;
        }
        else {
          $params->{component_id} = IS_NULL;
        }
      }
      else {
        $params->{product_id}   = IS_NULL;
        $params->{component_id} = IS_NULL;
      }

      if (@{Bugzilla::Extension::BugmailFilter::Filter->match($params)}) {
        ThrowUserError('bugmail_filter_exists');
      }
      $params->{action} = $input->{action} eq 'Exclude' ? 1 : 0;
      foreach my $name (keys %$params) {
        $params->{$name} = undef if $params->{$name} eq IS_NULL;
      }
      Bugzilla::Extension::BugmailFilter::Filter->create($params);
    }

    elsif ($input->{remove_filter}) {

      # remove filter(s)

      my $ids  = ref($input->{remove}) ? $input->{remove} : [$input->{remove}];
      my $dbh  = Bugzilla->dbh;
      my $user = Bugzilla->user;

      my $filters = Bugzilla::Extension::BugmailFilter::Filter->match(
        {id => $ids, user_id => $user->id});
      $dbh->bz_start_transaction;
      foreach my $filter (@$filters) {
        $filter->remove_from_db();
      }
      $dbh->bz_commit_transaction;
    }
  }

  my $vars        = $args->{vars};
  my $field_descs = template_var('field_descs');

  # load all fields into a hash for easy manipulation
  my %fields = map { $_->name => $field_descs->{$_->name} }
    @{Bugzilla->fields({obsolete => 0})};

  # remove time trackinger fields
  if (!Bugzilla->user->is_timetracker) {
    foreach my $field (TIMETRACKING_FIELDS) {
      delete $fields{$field};
    }
  }

  # remove fields which don't make any sense to filter on
  foreach my $field (IGNORE_FIELDS) {
    delete $fields{$field};
  }

  # remove all tracking flag fields.  these change too frequently to be of
  # value, so they only add noise to the list.
  foreach my $field (Bugzilla->tracking_flag_names) {
    delete $fields{$field};
  }

  # add tracking flag types instead
  foreach my $field (
    @{Bugzilla::Extension::BugmailFilter::FakeField->tracking_flag_fields()})
  {
    $fields{$field->name} = $field->description;
  }

  # adjust the description for selected fields
  foreach my $field (keys %{FIELD_DESCRIPTION_OVERRIDE()}) {
    $fields{$field} = FIELD_DESCRIPTION_OVERRIDE->{$field};
  }

  # some fields are present in the changed-fields x-header but are not real
  # bugzilla fields
  foreach
    my $field (@{Bugzilla::Extension::BugmailFilter::FakeField->fake_fields()})
  {
    $fields{$field->name} = $field->description;
  }

  $vars->{fields} = \%fields;
  $vars->{field_list} = [sort { lc($a->{description}) cmp lc($b->{description}) }
      map { {name => $_, description => $fields{$_}} } keys %fields];

  $vars->{relationships} = FILTER_RELATIONSHIPS();

  $vars->{filters} = [
    sort {
           $a->product_name cmp $b->product_name
        || $a->component_name cmp $b->component_name
        || $a->field_name cmp $b->field_name
    } @{Bugzilla::Extension::BugmailFilter::Filter->match({
        user_id => Bugzilla->user->id,
      })
    }
  ];

  # set field_description
  foreach my $filter (@{$vars->{filters}}) {
    my $field_name = $filter->field_name;
    if (!$field_name) {
      $filter->field_description('Any');
    }
    elsif (substr($field_name, 0, 1) eq '~') {
      $filter->field_description('~ ' . substr($field_name, 1));
    }
    else {
      $filter->field_description($fields{$field_name} || $filter->field->description);
    }
  }

  # build a list of tracking-flags, grouped by type
  require Bugzilla::Extension::TrackingFlags::Constants;
  require Bugzilla::Extension::TrackingFlags::Flag;
  my %flag_types = map { $_->{name} => $_->{description} }
    @{Bugzilla::Extension::TrackingFlags::Constants::FLAG_TYPES()};
  my %tracking_flags_by_type;
  foreach my $flag (Bugzilla::Extension::TrackingFlags::Flag->get_all) {
    my $type = $flag_types{$flag->flag_type};
    $tracking_flags_by_type{$type} //= [];
    push @{$tracking_flags_by_type{$type}}, $flag;
  }
  my @tracking_flags_by_type;
  foreach my $type (sort keys %tracking_flags_by_type) {
    push @tracking_flags_by_type,
      {name => $type, flags => $tracking_flags_by_type{$type},};
  }
  $vars->{tracking_flags_by_type} = \@tracking_flags_by_type;

  ${$args->{handled}} = 1;
}

#
# hooks
#

sub user_wants_mail {
  my ($self, $args) = @_;
  my ($user, $wants_mail, $diffs, $comments)
    = @$args{qw( user wants_mail fieldDiffs comments )};

  # already filtered by email prefs
  return unless $$wants_mail;

  # avoid recursion
  my $depth = 0;
  for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
    $depth++ if $sub eq 'Bugzilla::User::wants_bug_mail';
  }
  return if $depth > 1;

  my $cache = Bugzilla->request_cache->{bugmail_filters} //= {};
  my $filters = $cache->{$user->id}
    //= Bugzilla::Extension::BugmailFilter::Filter->match({user_id => $user->id});
  return unless @$filters;

  my $fields = [
    map { {
      filter_field => $_->{field_name},    # filter's field_name
      field_name   => $_->{field_name},    # raw bugzilla field_name
    } } grep {

      # flags are added later
      $_->{field_name} ne 'flagtypes.name'
    } @$diffs
  ];

  # if more than one field was changed we need to check if the normal email
  # preferences would have excluded the field.
  if (@$fields > 1) {

    # check each field individually and create filter objects if required
    my @arg_list
      = @$args{qw( bug relationship fieldDiffs comments dep_mail changer )};
    foreach my $field (@$fields) {

      # just a single diff
      foreach my $diff (@$diffs) {
        next unless $diff->{field_name} eq $field->{field_name};
        $arg_list[2] = [$diff];
        last;
      }
      if (!$user->wants_bug_mail(@arg_list)) {

        # changes to just this field would have been dropped by email
        # preferences.  build a corresponding filter object so we
        # interact with email preferences correctly.
        push @$filters,
          Bugzilla::Extension::BugmailFilter::Filter->new_from_hash({
          field_name => $field->{field_name}, action => 1,
          });
      }
    }
  }

  # insert fake fields for new attachments and comments
  if (@$comments) {
    if (grep { $_->type == CMT_ATTACHMENT_CREATED } @$comments) {
      push @$fields,
        {field_name => 'attachment.created', filter_field => 'attachment.created'};
    }
    if (grep { $_->type != CMT_ATTACHMENT_CREATED } @$comments) {
      push @$fields,
        {field_name => 'comment.created', filter_field => 'comment.created'};
    }
  }

  # insert fake fields for flags
  foreach my $diff (@$diffs) {
    next unless $diff->{field_name} eq 'flagtypes.name';
    foreach my $change (split(/, /, join(', ', ($diff->{old}, $diff->{new})))) {
      next unless $change =~ /^(.+)[\?\-+]/;
      push @$fields, {filter_field => $1, field_name => 'flagtypes.name',};
    }
  }

  # set filter_field on tracking flags to tracking.$type
  require Bugzilla::Extension::TrackingFlags::Flag;
  my @tracking_flags = Bugzilla->tracking_flags;
  foreach my $field (@$fields) {
    next unless my $field_name = $field->{field_name};
    foreach my $tracking_flag (@tracking_flags) {
      if ($field_name eq $tracking_flag->name) {
        $field->{filter_field} = 'tracking.' . $tracking_flag->flag_type;
      }
    }
  }

  if (_should_drop($fields, $filters, $args)) {
    $$wants_mail = 0;
    openlog('apache', 'cons,pid', 'local4');
    syslog(
      'notice',
      encode_utf8(sprintf(
        '[bugmail] %s (filtered) bug-%s %s',
        $args->{user}->login,
        $args->{bug}->id, $args->{bug}->short_desc,
      ))
    );
    closelog();
  }
}

sub _should_drop {
  my ($fields, $filters, $args) = @_;

  # calculate relationships

  my ($user, $bug, $relationship, $changer)
    = @$args{qw( user bug relationship changer )};
  my ($user_id, $login) = ($user->id, $user->login);
  my $bit_direct   = Bugzilla::BugMail::BIT_DIRECT;
  my $bit_watching = Bugzilla::BugMail::BIT_WATCHING;
  my $bit_compwatch = 15;    # from Bugzilla::Extension::ComponentWatching

  # the index of $rel_map corresponds to the values in FILTER_RELATIONSHIPS
  my @rel_map;
  $rel_map[1] = $bug->assigned_to->id == $user_id;
  $rel_map[2] = !$rel_map[1];
  $rel_map[3] = $bug->reporter->id == $user_id;
  $rel_map[4] = !$rel_map[3];
  if ($bug->qa_contact) {
    $rel_map[5] = $bug->qa_contact->id == $user_id;
    $rel_map[6] = !$rel_map[6];
  }
  $rel_map[7] = $bug->cc ? grep { $_ eq $login } @{$bug->cc} : 0;
  $rel_map[8] = !$rel_map[8];
  $rel_map[9] = ($relationship & $bit_watching or $relationship & $bit_compwatch);
  $rel_map[10] = !$rel_map[9];
  $rel_map[11] = $bug->is_mentor($user);
  $rel_map[12] = !$rel_map[11];
  foreach my $bool (@rel_map) {
    $bool = $bool ? 1 : 0;
  }

  # exclusions
  # drop email where we are excluding all changed fields

  my $params = {
    product_id   => $bug->product_id,
    component_id => $bug->component_id,
    rel_map      => \@rel_map,
    changer_id   => $changer->id,
  };

  foreach my $field (@$fields) {
    $params->{field} = $field;
    foreach my $filter (grep { $_->is_exclude } @$filters) {
      if ($filter->matches($params)) {
        $field->{exclude} = 1;
        last;
      }
    }
  }

  # no need to process includes if nothing was excluded
  if (!grep { $_->{exclude} } @$fields) {
    return 0;
  }

  # inclusions
  # flip the bit for fields that should be included

  foreach my $field (@$fields) {
    $params->{field} = $field;
    foreach my $filter (grep { $_->is_include } @$filters) {
      if ($filter->matches($params)) {
        $field->{exclude} = 0;
        last;
      }
    }
  }

  # drop if all fields are still excluded
  return !(grep { !$_->{exclude} } @$fields);
}

# catch when fields are renamed, and update the field_name entires
sub object_end_of_update {
  my ($self, $args) = @_;
  my $object = $args->{object};

  return
    unless $object->isa('Bugzilla::Field')
    || $object->isa('Bugzilla::Extension::TrackingFlags::Flag');

  return unless exists $args->{changes}->{name};

  my $old_name = $args->{changes}->{name}->[0];
  my $new_name = $args->{changes}->{name}->[1];

  Bugzilla->dbh->do("UPDATE bugmail_filters SET field_name=? WHERE field_name=?",
    undef, $new_name, $old_name);
}

sub reorg_move_component {
  my ($self, $args) = @_;
  my $new_product = $args->{new_product};
  my $component   = $args->{component};

  Bugzilla->dbh->do(
    "UPDATE bugmail_filters SET product_id=? WHERE component_id=?",
    undef, $new_product->id, $component->id,);
}

#
# schema / install
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{schema}->{bugmail_filters} = {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'},
      },
      field_name => {

        # due to fake fields, this can't be field_id
        TYPE    => 'VARCHAR(64)',
        NOTNULL => 0,
      },
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'},
      },
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE'},
      },
      changer_id => {
        TYPE       => 'INT3',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'},
      },
      relationship => {TYPE => 'INT2', NOTNULL => 0,},
      action       => {TYPE => 'INT1', NOTNULL => 1,},
    ],
    INDEXES => [
      bugmail_filters_unique_idx => {
        FIELDS => [
          qw( user_id field_name product_id component_id
            relationship )
        ],
        TYPE => 'UNIQUE',
      },
      bugmail_filters_user_idx => ['user_id',],
    ],
  };
}

sub install_update_db {
  Bugzilla->dbh->bz_add_column('bugmail_filters', 'changer_id',
    {TYPE => 'INT3', NOTNULL => 0,});
}

sub db_sanitize {
  my $dbh = Bugzilla->dbh;
  print "Deleting bugmail filters...\n";
  $dbh->do("DELETE FROM bugmail_filters");
}

__PACKAGE__->NAME;
