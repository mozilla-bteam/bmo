# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Group;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::API::V1::Util qw(validate translate params_to_objects);

use constant MAPPED_RETURNS =>
  {userregexp => 'user_regexp', isactive => 'is_active'};

sub create {
  my ($self, $params) = @_;

  Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->user->in_group('creategroups')
    || ThrowUserError("auth_failure",
    {group => "creategroups", action => "add", object => "group"});

  # Create group
  my $group = Bugzilla::Group->create({
    name        => $params->{name},
    description => $params->{description},
    userregexp  => $params->{user_regexp},
    isactive    => $params->{is_active},
    isbuggroup  => 1,
    icon_url    => $params->{icon_url}
  });
  return {id => $self->type('int', $group->id)};
}

sub update {
  my ($self, $params) = @_;

  my $dbh = Bugzilla->dbh;

  Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->user->in_group('creategroups')
    || ThrowUserError("auth_failure",
    {group => "creategroups", action => "edit", object => "group"});

  defined($params->{names})
    || defined($params->{ids})
    || ThrowCodeError('params_required',
    {function => 'Group.update', params => ['ids', 'names']});

  my $group_objects = params_to_objects($params, 'Bugzilla::Group');

  my %values = %$params;

  # We delete names and ids to keep only new values to set.
  delete $values{names};
  delete $values{ids};

  $dbh->bz_start_transaction();
  foreach my $group (@$group_objects) {
    $group->set_all(\%values);
  }

  my %changes;
  foreach my $group (@$group_objects) {
    my $returned_changes = $group->update();
    $changes{$group->id} = translate($returned_changes, MAPPED_RETURNS);
  }
  $dbh->bz_commit_transaction();

  my @result;
  foreach my $group (@$group_objects) {
    my %hash = (id => $group->id, changes => {},);
    foreach my $field (keys %{$changes{$group->id}}) {
      my $change = $changes{$group->id}->{$field};
      $hash{changes}{$field} = {
        removed => $self->type('string', $change->[0]),
        added   => $self->type('string', $change->[1])
      };
    }
    push(@result, \%hash);
  }

  return {groups => \@result};
}

sub get {
  my ($self, $params) = validate(@_, 'ids', 'names', 'type');

  Bugzilla->login(LOGIN_REQUIRED);

  # Reject access if there is no sense in continuing.
  my $user = Bugzilla->user;
  my $all_groups
    = $user->in_group('editusers') || $user->in_group('creategroups');
  if (!$all_groups && !$user->can_bless) {
    ThrowUserError('group_cannot_view');
  }

  Bugzilla->switch_to_shadow_db();

  my $groups = [];

  if (defined $params->{ids}) {

    # Get the groups by id
    $groups = Bugzilla::Group->new_from_list($params->{ids});
  }

  if (defined $params->{names}) {

    # Get the groups by name. Check will throw an error if a bad name is given
    foreach my $name (@{$params->{names}}) {

      # Skip if we got this from params->{id}
      next if grep { $_->name eq $name } @$groups;

      push @$groups, Bugzilla::Group->check({name => $name});
    }
  }

  if (!defined $params->{ids} && !defined $params->{names}) {
    if ($all_groups) {
      @$groups = Bugzilla::Group->get_all;
    }
    else {
      # Get only groups the user has bless groups too
      $groups = $user->bless_groups;
    }
  }

  # Now create a result entry for each.
  my @groups = map { $self->_group_to_hash($params, $_) } @$groups;
  return {groups => \@groups};
}

sub _group_to_hash {
  my ($self, $params, $group) = @_;
  my $user = Bugzilla->user;

  my $field_data = {
    id          => $self->type('int',    $group->id),
    name        => $self->type('string', $group->name),
    description => $self->type('string', $group->description),
  };

  if ($user->in_group('creategroups')) {
    $field_data->{is_active}    = $self->type('boolean', $group->is_active);
    $field_data->{is_bug_group} = $self->type('boolean', $group->is_bug_group);
    $field_data->{user_regexp}  = $self->type('string',  $group->user_regexp);
  }

  if ($params->{membership}) {
    $field_data->{membership} = $self->_get_group_membership($group, $params);
  }
  return $field_data;
}

sub _get_group_membership {
  my ($self, $group, $params) = @_;
  my $user = Bugzilla->user;

  my %users_only;
  my $dbh       = Bugzilla->dbh;
  my $editusers = $user->in_group('editusers');

  my $query = 'SELECT userid FROM profiles';
  my $visibleGroups;

  if (!$editusers && Bugzilla->params->{'usevisibilitygroups'}) {

    # Show only users in visible groups.
    $visibleGroups = $user->visible_groups_inherited;

    if (scalar @$visibleGroups) {
      $query .= qq{, user_group_map AS ugm
                         WHERE ugm.user_id = profiles.userid
                           AND ugm.isbless = 0
                           AND } . $dbh->sql_in('ugm.group_id', $visibleGroups);
    }
  }
  elsif ($editusers
    || $user->can_bless($group->id)
    || $user->in_group('creategroups'))
  {
    $visibleGroups = 1;
    $query .= qq{, user_group_map AS ugm
                     WHERE ugm.user_id = profiles.userid
                       AND ugm.isbless = 0
                    };
  }
  if (!$visibleGroups) {
    ThrowUserError('group_not_visible', {group => $group});
  }

  my $grouplist = Bugzilla::Group->flatten_group_membership($group->id);
  $query .= ' AND ' . $dbh->sql_in('ugm.group_id', $grouplist);

  my $userids      = $dbh->selectcol_arrayref($query);
  my $user_objects = Bugzilla::User->new_from_list($userids);
  my @users        = map { {
    id                => $self->type('int',     $_->id),
    real_name         => $self->type('string',  $_->name),
    nick              => $self->type('string',  $_->nick),
    name              => $self->type('string',  $_->login),
    email             => $self->type('string',  $_->email),
    can_login         => $self->type('boolean', $_->is_enabled),
    email_enabled     => $self->type('boolean', $_->email_enabled),
    login_denied_text => $self->type('string',  $_->disabledtext),
  } } @$user_objects;

  return \@users;
}

1;
