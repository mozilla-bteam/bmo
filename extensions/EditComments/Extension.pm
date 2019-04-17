# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::EditComments;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Bug;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Config::Common;
use Bugzilla::Config::GroupSecurity;

our $VERSION = '1.0';

################
# Installation #
################

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  my $schema = $args->{schema};

  $schema->{'longdescs_activity'} = {
    FIELDS => [
      comment_id => {
        TYPE    => 'INT',
        NOTNULL => 1,
        REFERENCES =>
          {TABLE => 'longdescs', COLUMN => 'comment_id', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      change_when => {TYPE => 'DATETIME', NOTNULL => 1},
      old_comment => {TYPE => 'LONGTEXT', NOTNULL => 1},
      is_hidden   => {TYPE => 'BOOLEAN',  NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      longdescs_activity_comment_id_idx             => ['comment_id'],
      longdescs_activity_change_when_idx            => ['change_when'],
      longdescs_activity_comment_id_change_when_idx => [qw(comment_id change_when)],
    ],
  };
}

sub install_update_db {
  my $dbh = Bugzilla->dbh;
  $dbh->bz_add_column('longdescs', 'edit_count', {TYPE => 'INT3', DEFAULT => 0});

  # Add the new `is_hidden` column to the `longdescs_activity` table, which
  # has been introduced with the extension's version 1.0, defaulting to `true`
  # because existing admin-edited revisions may contain sensitive info
  $dbh->bz_add_column('longdescs_activity', 'is_hidden',
    {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 1});
}

####################
# Template Methods #
####################

sub page_before_template {
  my ($self, $args) = @_;

  return if $args->{'page_id'} ne 'comment-revisions.html';

  my $vars   = $args->{'vars'};
  my $user   = Bugzilla->user;
  my $params = Bugzilla->input_params;

  my $bug_id = $params->{bug_id};
  my $bug    = Bugzilla::Bug->check($bug_id);

  my $comment_id = $params->{comment_id};

  my ($comment) = grep($_->id == $comment_id, @{$bug->comments});
  if (!$comment || ($comment->is_private && !$user->is_insider)) {
    ThrowUserError("edit_comment_invalid_comment_id", {comment_id => $comment_id});
  }

  $vars->{'bug'}     = $bug;
  $vars->{'comment'} = $comment;
}

##################
# Object Methods #
##################

BEGIN {
  no warnings 'redefine';
  *Bugzilla::Comment::activity   = \&_get_activity;
  *Bugzilla::Comment::edit_count = \&_edit_count;
}

sub _edit_count { return $_[0]->{'edit_count'}; }

sub _get_activity {
  my ($self, $activity_sort_order) = @_;

  return $self->{'activity'} if $self->{'activity'};

  my $dbh = Bugzilla->dbh;
  my $query
    = 'SELECT longdescs_activity.comment_id AS id, profiles.userid, '
    . $dbh->sql_date_format('longdescs_activity.change_when', '%Y-%m-%d %H:%i:%s')
    . '
                        AS time, longdescs_activity.old_comment AS old,
                        longdescs_activity.is_hidden as is_hidden
                   FROM longdescs_activity
             INNER JOIN profiles
                     ON profiles.userid = longdescs_activity.who
                  WHERE longdescs_activity.comment_id = ?';
  $query .= " ORDER BY longdescs_activity.change_when DESC";
  my $sth = $dbh->prepare($query);
  $sth->execute($self->id);

  # We are shifting each comment activity body 1 back. The reason this
  # has to be done is that the longdescs_activity table stores the comment
  # body that the comment was before the edit, not the actual new version
  # of the comment.
  my @activity;
  my $prev_rev;
  my $count = 0;
  while (my $revision = $sth->fetchrow_hashref()) {
    my $current = $count == 0;
    push(
      @activity,
      {
        author       => Bugzilla::User->new({id => $revision->{userid}, cache => 1}),
        created_time => $revision->{time},
        old          => $revision->{old},
        revised_time => $current ? undef : $prev_rev->{time},
        new          => $current ? $self->body : $prev_rev->{old},
        is_hidden    => $current ? 0 : $prev_rev->{is_hidden},
      }
    );
    $prev_rev = $revision;
    $count++;
  }

  return [] if !@activity;

  # Store the original comment as the first or last entry
  # depending on sort order
  push(
    @activity,
    {
      author       => $self->author,
      created_time => $self->creation_ts,
      revised_time => $prev_rev->{time},
      new          => $prev_rev->{old},
      is_hidden    => $prev_rev->{is_hidden},
    }
  );

  $activity_sort_order
    ||= Bugzilla->user->settings->{'comment_sort_order'}->{'value'};

  if ($activity_sort_order eq "oldest_to_newest") {
    @activity = reverse @activity;
  }

  $self->{'activity'} = \@activity;

  return $self->{'activity'};
}

#########
# Hooks #
#########

sub object_columns {
  my ($self,  $args)    = @_;
  my ($class, $columns) = @$args{qw(class columns)};
  if ($class->isa('Bugzilla::Comment')) {
    push(@$columns, 'edit_count');
  }
}

sub bug_end_of_update {
  my ($self, $args) = @_;

  # Silently return if not in the proper group
  # or if editing comments is disabled
  my $user                = Bugzilla->user;
  my $edit_comments_group = Bugzilla->params->{edit_comments_group};
  return
    unless $user->is_insider
    || $edit_comments_group && $user->in_group($edit_comments_group);

  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};
  my $params    = Bugzilla->input_params;
  my $dbh       = Bugzilla->dbh;

  my $updated = 0;
  foreach my $param (grep(/^edit_comment_textarea_/, keys %$params)) {
    my ($comment_id) = $param =~ /edit_comment_textarea_(\d+)$/;
    next if !detaint_natural($comment_id);

    # The comment ID must belong to this bug.
    my ($comment_obj) = grep($_->id == $comment_id, @{$bug->comments});
    next if (!$comment_obj || ($comment_obj->is_private && !$user->is_insider));

# Insiders can edit any comment while unprivileged users can only edit their own comments
    next unless $user->is_insider || $comment_obj->author->id == $user->id;

    my $new_comment = $comment_obj->_check_thetext($params->{$param});

    my $old_comment = $comment_obj->body;
    next if $old_comment eq $new_comment;

    # Insiders can hide comment revisions where needed
    my $is_hidden
      = (  $user->is_insider
        && defined $params->{"edit_comment_checkbox_$comment_id"}
        && $params->{"edit_comment_checkbox_$comment_id"} == 'on') ? 1 : 0;

    $dbh->do(
      "UPDATE longdescs SET thetext = ?, edit_count = edit_count + 1
                  WHERE comment_id = ?", undef, $new_comment, $comment_id
    );
    Bugzilla->memcached->clear({table => 'longdescs', id => $comment_id});

    # Log old comment to the longdescs activity table
    $timestamp ||= $dbh->selectrow_array("SELECT NOW()");
    $dbh->do(
      "INSERT INTO longdescs_activity "
        . "(comment_id, who, change_when, old_comment, is_hidden) "
        . "VALUES (?, ?, ?, ?, ?)",
      undef,
      ($comment_id, $user->id, $timestamp, $old_comment, $is_hidden)
    );

    $comment_obj->{thetext} = $new_comment;

    $updated = 1;
  }

  $bug->_sync_fulltext(update_comments => 1) if $updated;
}

sub config_modify_panels {
  my ($self, $args) = @_;
  push @{$args->{panels}->{groupsecurity}->{params}},
    {
    name    => 'edit_comments_group',
    type    => 's',
    choices => \&get_all_group_names,
    default => 'editbugs',
    checker => \&check_group
    };
}

sub webservice {
  my ($self, $args) = @_;
  my $dispatch = $args->{dispatch};
  $dispatch->{EditComments} = "Bugzilla::Extension::EditComments::WebService";
}

sub db_sanitize {
  my $dbh = Bugzilla->dbh;
  print "Deleting edited comment histories...\n";
  $dbh->do("DELETE FROM longdescs_activity");
  $dbh->do("UPDATE longdescs SET edit_count=0");
}

__PACKAGE__->NAME;
