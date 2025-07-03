# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Util;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::User;
use Bugzilla::Types qw(:types);
use Bugzilla::Util  qw(mojo_user_agent trim);
use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Types qw(:types);

use List::MoreUtils qw(any);
use List::Util      qw(any first);
use Try::Tiny;
use Type::Params qw( compile );
use Type::Utils;
use Types::Standard qw( :types );
use Mojo::JSON      qw(encode_json);

use base qw(Exporter);

our @EXPORT = qw(
  create_revision_attachment
  get_attachment_revisions
  get_bug_role_phids
  intersect
  is_attachment_phab_revision
  is_bug_assigned
  request
  set_attachment_approval_flags
  set_phab_user
  set_reviewer_rotation
);

use constant LEGACY_APPROVAL_MAPPING => {
  'firefox-beta'    => 'beta',
  'firefox-release' => 'release',
  'firefox-esr115'  => 'esr115',
  'firefox-esr128'  => 'esr128',
  'firefox-esr140'  => 'esr140',
};

# Set approval flags on Phabricator revision bug attachments.
sub set_attachment_approval_flags {
  my ($attachment, $revision, $phab_user, $is_new) = @_;
  my $bmo_user = $phab_user->bugzilla_user;

  my $revision_status_flag_map = {
    'abandoned'       => '-',
    'accepted'        => '+',
    'accepted-prior'  => '+',
    'changes-planned' => 'X',
    'draft'           => '?',
    'needs-review'    => '?',
    'needs-revision'  => '-',
  };

  # Find the current review status of the revision changer
  my $status          = undef;
  my $reviewer_status = undef;

  if ($is_new) {
    $reviewer_status = $revision->status;
    $status          = $revision_status_flag_map->{$reviewer_status};
  }
  else {
    foreach my $reviewer (@{$revision->reviews}) {
      if ($reviewer->{user}->id == $phab_user->id) {
        $reviewer_status = $reviewer->{status};
        $status          = $revision_status_flag_map->{$reviewer_status};
        last;
      }
    }
  }

  if (!$status) {
    INFO( "Approval flag status not found for revision status '"
        . $reviewer_status
        . "'");
    return;
  }

  # The repo short name is the appropriate value that aligns with flag names.
  my $repo_name = $revision->repository->short_name;

  # With the move to git some repository short names in Phabricator changed but
  # we want to use the old approval flags so we map the new names to the old if
  # they exist
  $repo_name = LEGACY_APPROVAL_MAPPING->{$repo_name} || $repo_name;

  my $approval_flag_name = "approval-mozilla-$repo_name";

  my @old_flags;
  my @new_flags;

  INFO( 'Setting revision D'
      . $revision->id
      . ' with '
      . $reviewer_status
      . ' status to '
      . $approval_flag_name
      . $status);

  # Find the current approval flag state if it exists.
  foreach my $flag (@{$attachment->flags}) {

    # Ignore for all flags except the approval flag.
    next if $flag->name ne $approval_flag_name;

    # Set the flag to it's new status. If it already has that status,
    # it will be a non-change. We also need to check to make sure the
    # flag change is allowed.
    if (!$bmo_user->can_change_flag($flag->type, $flag->status, $status)) {
      INFO(
        "Unable to set existing `$approval_flag_name` flag to `$status` due to permissions."
      );
      return;
    }

    # If setting to + then the Phabricator user needs to be a release manager.
    if (($status eq '+' || $status eq '-') && !$phab_user->is_release_manager) {
      INFO(
        "Unable to set existing `$approval_flag_name` flag to `$status` due to not being a release manager."
      );
      return;
    }

    INFO("Set existing `$approval_flag_name` flag to `$status`.");
    push @old_flags, {id => $flag->id, status => $status};
    last;
  }

  # If we didn't find an existing approval flag to update, add it now.
  # Also check to make sure we have permission to create the flag.
  if (!@old_flags && $status ne 'X') {
    my $approval_flag = Bugzilla::FlagType->new({name => $approval_flag_name});
    if ($approval_flag) {

  # If setting to + then at least one accepted reviewer needs to be a release manager.
      if ($status eq '+' && !$phab_user->is_release_manager) {
        INFO(
          "Unable to create new `$approval_flag_name` flag with status `$status` due to not being accepted by a release manager."
        );
        return;
      }

      if ($bmo_user->can_change_flag($approval_flag, 'X', $status)) {
        INFO("Creating new `$approval_flag_name` flag with status `$status`");
        push @new_flags,
          {setter => $bmo_user, status => $status, type_id => $approval_flag->id,};
      }
      else {
        INFO(
          "Unable to create new `$approval_flag_name` flag with status `$status` due to permissions."
        );
      }
    }
    else {
      INFO("Approval flag $approval_flag_name type not found");
    }
  }

  $attachment->set_flags(\@old_flags, \@new_flags);
}

sub create_revision_attachment {
  state $check = compile(Bug, Revision, Str, User);
  my ($bug, $revision, $timestamp, $submitter) = $check->(@_);

  my $phab_base_uri = Bugzilla->params->{phabricator_base_uri};
  ThrowUserError('invalid_phabricator_uri') unless $phab_base_uri;

  my $revision_uri = $phab_base_uri . "D" . $revision->id;

  # Check for previous attachment with same revision id.
  # If one matches then return it instead. This is fine as
  # BMO does not contain actual diff content.
  my @review_attachments
    = grep { is_attachment_phab_revision($_) } @{$bug->attachments};
  my $attachment = first { trim($_->data) eq $revision_uri } @review_attachments;


  if (!defined $attachment) {

    # No attachment is present, so we can now create new one

    if (!$timestamp) {
      ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");
    }

    # If submitter, then switch to that user when creating attachment
    local $submitter->{groups} = [Bugzilla::Group->get_all];    # We need to always be able to add attachment
    my $restore_prev_user = Bugzilla->set_user($submitter, scope_guard => 1);

    $attachment = Bugzilla::Attachment->create({
      bug         => $bug,
      creation_ts => $timestamp,
      data        => $revision_uri,
      description => $revision->title,
      filename    => 'phabricator-D' . $revision->id . '-url.txt',
      ispatch     => 0,
      isprivate   => 0,
      mimetype    => PHAB_CONTENT_TYPE,
    });

    # Insert a comment about the new attachment into the database.
    $bug->add_comment(
      $revision->summary,
      {
        type        => CMT_ATTACHMENT_CREATED,
        extra_data  => $attachment->id,
        is_markdown => (Bugzilla->params->{use_markdown} ? 1 : 0)
      }
    );

    INFO('New attachment ' . $attachment->id . ' created');
  }
  else {
    INFO('Existing attachment ' . $attachment->id . ' found');
  }

  return $attachment;
}

sub intersect {
  my ($list1, $list2) = @_;
  my %e = map { $_ => undef } @{$list1};
  return grep { exists($e{$_}) } @{$list2};
}

sub get_bug_role_phids {
  state $check = compile(Bug);
  my ($bug) = $check->(@_);

  my @bug_users = ($bug->reporter);
  push(@bug_users, $bug->assigned_to) if is_bug_assigned($bug);
  push(@bug_users, $bug->qa_contact)  if $bug->qa_contact;
  push(@bug_users, @{$bug->cc_users}) if @{$bug->cc_users};

  my $phab_users = Bugzilla::Extension::PhabBugz::User->match(
    {ids => [map { $_->id } @bug_users]});

  return [map { $_->phid } @{$phab_users}];
}

sub is_bug_assigned {
  return $_[0]->assigned_to->email ne 'nobody@mozilla.org';
}

sub is_attachment_phab_revision {
  state $check = compile(Attachment);
  my ($attachment) = $check->(@_);
  return $attachment->contenttype eq PHAB_CONTENT_TYPE;
}

sub get_attachment_revisions {
  state $check = compile(Bug);
  my ($bug) = $check->(@_);

  my @attachments
    = grep { is_attachment_phab_revision($_) } @{$bug->attachments()};

  return unless @attachments;

  my @revision_ids;
  foreach my $attachment (@attachments) {
    my ($revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
    next if !$revision_id;
    push(@revision_ids, int($revision_id));
  }

  return unless @revision_ids;

  my @revisions;
  foreach my $revision_id (@revision_ids) {
    my $revision = Bugzilla::Extension::PhabBugz::Revision->new_from_query(
      {ids => [$revision_id]});
    push @revisions, $revision if $revision;
  }

  return \@revisions;
}

sub request {
  state $check = compile(Str, HashRef, Optional [Bool]);
  my ($method, $data, $no_die) = $check->(@_);
  my $request_cache = Bugzilla->request_cache;
  my $params        = Bugzilla->params;
  my $ua            = $request_cache->{phabricator_ua} ||= mojo_user_agent();

  my $phab_api_key = $params->{phabricator_api_key};
  ThrowUserError('invalid_phabricator_api_key') unless $phab_api_key;
  my $phab_base_uri = $params->{phabricator_base_uri};
  ThrowUserError('invalid_phabricator_uri') unless $phab_base_uri;

  my $full_uri = $phab_base_uri . '/api/' . $method;

  $data->{__conduit__} = {token => $phab_api_key};

  my $response
    = $ua->post($full_uri => form => {params => encode_json($data)})->result;
  ThrowCodeError('phabricator_api_error', {reason => $response->message})
    if $response->is_error;

  my $result = $response->json;
  ThrowCodeError('phabricator_api_error', {reason => 'JSON decode failure'})
    if !defined($result);

  if ($result->{error_code} && !$no_die) {
    ThrowCodeError('phabricator_api_error',
      {code => $result->{error_code}, reason => $result->{error_info}});
  }

  return $result;
}

sub set_phab_user {
  my $user = Bugzilla::User->new({name => PHAB_AUTOMATION_USER});
  $user->{groups} = [Bugzilla::Group->get_all];

  return Bugzilla->set_user($user, scope_guard => 1);
}

sub set_reviewer_rotation {
  my ($revision) = @_;

  INFO('D' . $revision->id . ': Setting reviewer rotation');

  # Load a fresh version of the revision with Heralds changes.
  $revision = Bugzilla::Extension::PhabBugz::Revision->new_from_query(
    {phids => [$revision->phid]});

  # Map of phids to blocking status
  my $is_blocking = {};

# Find out what the project reviewers and individual reviewers are. If the revision
# has a reviewer group set, normally it ends in "-reviewer-rotation". Normally Herald
# will set this if certain conditions are met. If there are no review rotation groups,
# then do nothing.
  my @review_projects = get_review_rotation_projects($revision, $is_blocking);
  my @review_users    = get_review_users($revision, $is_blocking);

  if (!@review_projects) {
    INFO('Reviewer rotation projects not found');
    return;
  }

  INFO( 'Reviewer rotation project(s) '
      . (join ', ', map { $_->name } @review_projects)
      . ' found.');

  # If the revision is part of a stack, grab a list of current reviewers
  # and if one of the project members is a reviewer, then assign the same reviewer
  my @stack_reviewers = get_stack_reviewers($revision, $is_blocking);

  # Once the reviewer rotation groups are determined, query Phabricator for
  # list of group members for each and sort them by user ID descending.
  foreach my $project (@review_projects) {
    my $found_reviewer;

    my $project_members = [sort { $a->id <=> $b->id } @{$project->members}];

    foreach my $member (@{$project_members}) {

      # Make sure that none of the individual group members are not already
      # set as a reviewer. If so, then remove the rotation group and return.
      if (any { $_->id == $member->id } @review_users) {
        INFO(
          'Member of review rotation project already set as a reviewer. Removing review rotation project'
        );
        $revision->remove_reviewer($project->phid);
        $revision->update;
        next;
      }

      # If the member is one of the reviewers for a revision in the stack,
      # then use the same reviewer for this revision
      if (any { $_->id == $member->id } @stack_reviewers) {
        $found_reviewer = $member->phid;
        last;
      }
    }

    # If we did not find a stack reviewer, then start the round robin
    # process to find the next reviewer in the rotation
    if (!$found_reviewer) {
      my $dbh = Bugzilla->dbh;

      # Find the last selected reviewer for the rotation group
      my $last_reviewer_phid = find_last_reviewer_phid($project);

      my $index = 0;
      foreach my $member (@{$project_members}) {

        # If there is no member that was the last reviewer, then just pick the first
        # member in the list
        if (!$last_reviewer_phid) {
          $found_reviewer = $member;
        }

        # If the member was the last select reviewer, then we need to remove them,
        # and pick the next member in the list.
        if ($last_reviewer_phid eq $member->phid) {

          # Delete old reviewer
          delete_last_reviewer_phid($project, $last_reviewer_phid);

          # Select next member in order
          $found_reviewer = $project_members->[$index];
          $found_reviewer = $project_members->[0] if !$found_reviewer;    # Loop back around
        }

       # Once a potential reviewer has been found, look to see if they can see the bug,
       # and they are not set to away (not accepting reviews). If both are are negative,
       # we choose the next person in the list.
        if ( $found_reviewer
          && $found_reviewer->bugzilla_user->can_see_bug($revision->bug->id)
          && $found_reviewer->bugzilla_user->settings->{block_reviews}->{value} ne 'on')
        {
          INFO('Found new reviewer ' . $member->id);
          last;
        }
        else {
          $found_reviewer = undef;
        }

        $index++;
      }
    }

    if ($found_reviewer) {

      # Set the user as a reviewer on the revision.
      INFO('Adding new reviewer ' . $found_reviewer->id);
      if ($is_blocking->{$project->phid}) {
        $revision->add_reviewer('blocking(' . $found_reviewer->phid . ')');
      }
      else {
        $revision->add_reviewer($found_reviewer->phid);
      }

      # Remove the review rotation group.
      INFO('Removing reviewer project');
      $revision->remove_reviewer($project->phid);

      # Store the data in the phab_reviewer_rotation table so they will be
      # next time.
      add_last_reviewer_phid($project, $found_reviewer->phid);

      # Add new reviewer to review users list in case they are also
      # a member of the next review rotation group.
      push @review_users, $found_reviewer;
    }
  }

  # Save changes to the revision and return.
  $revision->update;
}

sub find_last_reviewer_phid {
  my ($project) = @_;
  INFO('Retrieving last reviewer for project ' . $project->phid);
  return Bugzilla->dbh->selectrow_array(
    'SELECT user_phid FROM phab_reviewer_rotation WHERE project_phid = ?',
    undef, $project->phid);
}

sub delete_last_reviewer_phid {
  my ($project, $reviewer_phid) = @_;
  INFO("Deleting last reviewer $reviewer_phid");
  Bugzilla->dbh->do(
    'DELETE FROM phab_reviewer_rotation WHERE project_phid = ? AND user_phid = ?',
    undef, $project->phid, $reviewer_phid);
}

sub add_last_reviewer_phid {
  my ($project, $reviewer_phid) = @_;
  INFO("Adding last reviewer $reviewer_phid");
  Bugzills->dbh->do(
    'INSERT INTO phab_reviewer_rotation (project_phid, user_phid) VALUES (?, ?)',
    undef, $project->phid, $reviewer_phid);
}

sub get_stack_reviewers {
  my ($revision, $is_blocking) = @_;
  my @stack_reviewers;

  INFO('Retrieving stack reviewers from all stack revisions');

  my ($stack_phids) = $revision->stack_graph;
  if (@{$stack_phids}) {
    foreach my $phid (@{$stack_phids}) {
      my $stack_revision
        = Bugzilla::Extension::PhabBugz::Revision->new_from_query({phids => [$phid]});
      next if !$stack_revision;
      foreach my $reviewer (@{$stack_revision->reviews}) {
        next if $reviewer->{is_project};
        push @stack_reviewers, $reviewer->{user};
        $is_blocking->{$reviewer->{user}->phid} = $reviewer->{is_blocking} ? 1 : 0;
      }
    }
  }

  return @stack_reviewers;
}

sub get_review_rotation_projects {
  my ($revision, $is_blocking);
  my @review_projects;

  INFO('Retrieving review rotation projects');

  foreach my $reviewer (@{$revision->reviews}) {

    # Only interested in projects
    next if !$reviewer->{is_project};

    # Only interested in reviewer rotation groups
    next if $reviewer->{user}->name !~ /-reviewer-rotation$/;

    push @review_projects, $reviewer->{user};
    $is_blocking->{$reviewer->{user}->phid} = $reviewer->{is_blocking} ? 1 : 0;
  }

  return @review_projects;
}

sub get_review_users {
  my ($revision, $is_blocking);
  my @review_users;

  INFO('Retrieving review users (not projects)');

  foreach my $reviewer (@{$revision->reviews}) {

    # Only interested in users, not projects
    next if $reviewer->{is_project};

    push @review_users, $reviewer->{user};
    $is_blocking->{$reviewer->{user}->phid} = $reviewer->{is_blocking} ? 1 : 0;
  }

  return @review_users;
}

1;
