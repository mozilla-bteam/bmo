#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Keyword;
use Bugzilla::Flag;
use Bugzilla::Status;
use Bugzilla::Token;
use Bugzilla::Hook;

use Scalar::Util qw(blessed);
use List::MoreUtils qw(firstidx);
use Storable qw(dclone);

my $user = Bugzilla->login(LOGIN_REQUIRED);

my $cgi      = Bugzilla->cgi;
my $dbh      = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars     = {};
my $C        = Bugzilla->request_cache->{mojo_controller};

######################################################################
# Subroutines
######################################################################

# Tells us whether or not a field should be changed by process_bug.
sub should_set {

  # check_defined is used for fields where there's another field
  # whose name starts with "defined_" and then the field name--it's used
  # to know when we did things like empty a multi-select or deselect
  # a checkbox.
  my ($field, $check_defined) = @_;
  my $cgi = Bugzilla->cgi;
  if (defined $cgi->param($field)
    || ($check_defined && defined $cgi->param("defined_$field")))
  {
    return 1;
  }
  return 0;
}

######################################################################
# Begin Data/Security Validation
######################################################################

# BMO: Don't allow updating of bugs if disabled
if (Bugzilla->params->{disable_bug_updates}) {
  ThrowErrorPage(
    'bug/process/updates-disabled.html.tmpl',
    'Bug updates are currently disabled.'
  );
}

# Create a list of objects for all bugs being modified in this request.
my @bug_objects;
if (defined $cgi->param('id')) {
  my $bug = Bugzilla::Bug->check(scalar $cgi->param('id'));
  $cgi->param('id', $bug->id);
  push(@bug_objects, $bug);
}
else {
  foreach my $i ($cgi->param()) {
    if ($i =~ /^id_([1-9][0-9]*)/) {
      my $id = $1;
      push(@bug_objects, Bugzilla::Bug->check($id));
    }
  }
}

# Make sure there are bugs to process.
scalar(@bug_objects) || ThrowUserError("no_bugs_chosen", {action => 'modify'});

my $first_bug = $bug_objects[0];   # Used when we're only updating a single bug.

# Delete any parameter set to 'dontchange'.
if (defined $cgi->param('dontchange')) {
  foreach my $name ($cgi->param) {
    next if $name eq 'dontchange';    # But don't delete dontchange itself!
         # Skip ones we've already deleted (such as "defined_$name").
    next if !defined $cgi->param($name);
    if ($cgi->param($name) eq $cgi->param('dontchange')) {
      $cgi->delete($name);
      $cgi->delete("defined_$name");
    }
  }
}

# do a match on the fields if applicable
# BMO: allow extensions to define custom user fields
my $user_match_fields = {
  'qa_contact'  => {'type' => 'single'},
  'newcc'       => {'type' => 'multi'},
  'masscc'      => {'type' => 'multi'},
  'assigned_to' => {'type' => 'single'},
};
Bugzilla::Hook::process('bug_user_match_fields',
  {fields => $user_match_fields});
Bugzilla::User::match_field($user_match_fields);

# Check for a mid-air collision. Currently this only works when updating
# an individual bug.
my $delta_ts = $cgi->param('delta_ts') || '';

if ($delta_ts) {
  my $delta_ts_z = datetime_from($delta_ts)
    or ThrowCodeError('invalid_timestamp', {timestamp => $delta_ts});

  my $first_delta_tz_z = datetime_from($first_bug->delta_ts);

  if ($first_delta_tz_z ne $delta_ts_z) {
    ($vars->{'operations'})
      = Bugzilla::Bug::GetBugActivity($first_bug->id, undef, $delta_ts);

    my $start_at = $cgi->param('longdesclength')
      or ThrowCodeError('undefined_field', {field => 'longdesclength'});

    # Always sort midair collision comments oldest to newest,
    # regardless of the user's personal preference.
    my $comments = $first_bug->comments({order => "oldest_to_newest"});

    # Show midair if previous changes made other than CC
    # and/or one or more comments were made
    my $do_midair = scalar @$comments > $start_at ? 1 : 0;

    if (!$do_midair) {
      foreach my $operation (@{$vars->{'operations'}}) {
        foreach my $change (@{$operation->{'changes'}}) {
          if ($change->{'fieldname'} ne 'cc') {
            $do_midair = 1;
            last;
          }
        }
        last if $do_midair;
      }
    }

    if ($do_midair) {
      $vars->{'title_tag'} = "mid_air";
      $vars->{'start_at'}  = $start_at;
      $vars->{'comments'}  = $comments;
      $vars->{'bug'}       = $first_bug;

      # The token contains the old delta_ts. We need a new one.
      $cgi->param('token', issue_hash_token([$first_bug->id, $first_bug->delta_ts]));

      # Warn the user about the mid-air collision and ask them what to do.
      print $cgi->header() unless Bugzilla->usage_mode == USAGE_MODE_EMAIL;
      $template->process("bug/process/midair.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
      exit;
    }
  }
}

# We couldn't do this check earlier as we first had to validate bug IDs
# and display the mid-air collision page if delta_ts changed.
# If we do a mass-change, we use session tokens.
my $token = $cgi->param('token');

if ($cgi->param('id')) {
  check_hash_token($token, [$first_bug->id, $delta_ts || $first_bug->delta_ts]);
}
else {
  check_token_data($token, 'buglist_mass_change', 'query.cgi');
}

######################################################################
# End Data/Security Validation
######################################################################

$vars->{'title_tag'} = "bug_processed";

my $action;
if (defined $cgi->param('id')) {
  $action = $user->setting('post_bug_submit_action');
  if ($action ne 'nothing' && $action ne 'same_bug' && $action ne 'next_bug') {
    ThrowCodeError("invalid_post_bug_submit_action");
  }

  if ($action eq 'next_bug') {
    my $bug_list_obj = $user->recent_search_for($first_bug);
    my @bug_list     = $bug_list_obj ? @{$bug_list_obj->bug_list} : ();
    my $cur          = firstidx { $_ eq $cgi->param('id') } @bug_list;
    if ($cur >= 0 && $cur < $#bug_list) {
      my $next_bug_id = $bug_list[$cur + 1];
      detaint_natural($next_bug_id);
      if ($next_bug_id and $user->can_see_bug($next_bug_id)) {

        # We create an object here so that $bug->send_changes can use it
        # when displaying the header.
        $vars->{'bug'} = new Bugzilla::Bug($next_bug_id);
      }
    }
  }

  # Include both action = 'same_bug' and 'nothing'.
  else {
    $vars->{'bug'}    = $first_bug;
    $vars->{'bugids'} = $first_bug->id;
  }
}
else {
  # param('id') is not defined when changing multiple bugs at once.
  $action = 'nothing';
}

# For each bug, we have to check if the user can edit the bug the product
# is currently in, before we allow them to change anything.
foreach my $bug (@bug_objects) {
  if (!Bugzilla->user->can_edit_product($bug->product_obj->id)) {
    ThrowUserError("product_edit_denied", {product => $bug->product});
  }
}

# Component, target_milestone, and version are in here just in case
# the 'product' field wasn't defined in the CGI. It doesn't hurt to set
# them twice.
my @set_fields = qw(op_sys rep_platform priority bug_severity bug_type
  component target_milestone version
  bug_file_loc status_whiteboard short_desc
  deadline remaining_time estimated_time
  work_time set_default_assignee set_default_qa_contact
  cclist_accessible reporter_accessible
  product confirm_product_change
  bug_status resolution dup_id bug_ignored);
push(@set_fields, 'assigned_to') if !$cgi->param('set_default_assignee');
push(@set_fields, 'qa_contact')  if !$cgi->param('set_default_qa_contact');
my %field_translation = (
  bug_type               => 'type',
  bug_severity           => 'severity',
  rep_platform           => 'platform',
  short_desc             => 'summary',
  bug_file_loc           => 'url',
  set_default_assignee   => 'reset_assigned_to',
  set_default_qa_contact => 'reset_qa_contact',
  confirm_product_change => 'product_change_confirmed',
);

my %set_all_fields = (other_bugs => \@bug_objects);
foreach my $field_name (@set_fields) {
  if (should_set($field_name, 1)) {
    my $param_name = $field_translation{$field_name} || $field_name;
    $set_all_fields{$param_name} = $cgi->param($field_name);
  }
}

if (should_set('keywords')) {
  my $action = $cgi->param('keywordaction') || '';

  # Backward-compatibility for Bugzilla 3.x and older.
  $action = 'remove' if $action eq 'delete';
  $action = 'set'    if $action eq 'makeexact';
  $set_all_fields{keywords}->{$action} = $cgi->param('keywords');
}
if (should_set('comment')) {
  $set_all_fields{comment} = {
    body       => scalar $cgi->param('comment'),
    is_private => scalar $cgi->param('comment_is_private'),
    is_markdown => Bugzilla->params->{use_markdown} ? 1 : 0,
  };
}
if (should_set('see_also')) {
  $set_all_fields{'see_also'}->{add} = [split(/[\s,]+/, $cgi->param('see_also'))];
}
if (should_set('remove_see_also')) {
  $set_all_fields{'see_also'}->{remove} = [$cgi->param('remove_see_also')];
}
foreach my $dep_field (qw(dependson blocked regressed_by regresses)) {
  if (should_set($dep_field)) {
    if (my $dep_action = $cgi->param("${dep_field}_action")) {
      $set_all_fields{$dep_field}->{$dep_action}
        = [split(/[\s,]+/, $cgi->param($dep_field))];
    }
    else {
      $set_all_fields{$dep_field}->{set} = $cgi->param($dep_field);
    }
  }
}

# Formulate the CC data into two arrays of users involved in this CC change.
if ( defined $cgi->param('newcc')
  or defined $cgi->param('addselfcc')
  or defined $cgi->param('removecc')
  or defined $cgi->param('masscc'))
{
  my (@cc_add, @cc_remove);

  # If masscc is defined, then we came from buglist and need to either add or
  # remove cc's... otherwise, we came from show_bug and may need to do both.
  if (defined $cgi->param('masscc')) {
    if ($cgi->param('ccaction') eq 'add') {
      @cc_add = $cgi->param('masscc');
    }
    elsif ($cgi->param('ccaction') eq 'remove') {
      @cc_remove = $cgi->param('masscc');
    }
  }
  else {
    @cc_add = $cgi->param('newcc');
    push(@cc_add, Bugzilla->user) if $cgi->param('addselfcc');

    # We came from show_bug which uses a select box to determine what cc's
    # need to be removed...
    if ($cgi->param('removecc') && $cgi->param('cc')) {
      @cc_remove = $cgi->param('cc');
    }
  }

  $set_all_fields{cc} = {add => \@cc_add, remove => \@cc_remove};
}

# Fields that can only be set on one bug at a time.
if (defined $cgi->param('id')) {

  # Since aliases are unique (like bug numbers), they can only be changed
  # for one bug at a time.
  if (Bugzilla->params->{"usebugaliases"} && defined $cgi->param('alias')) {
    $set_all_fields{alias} = $cgi->param('alias');
  }
}

my %is_private;
foreach my $field (grep(/^defined_isprivate/, $cgi->param())) {
  $field =~ /(\d+)$/;
  my $comment_id = $1;
  $is_private{$comment_id} = $cgi->param("isprivate_$comment_id");
}
$set_all_fields{comment_is_private} = \%is_private;

my @check_groups = $cgi->param('defined_groups');
my @set_groups   = $cgi->param('groups');
my ($removed_groups) = diff_arrays(\@check_groups, \@set_groups);
$set_all_fields{groups} = {add => \@set_groups, remove => $removed_groups};

my @custom_fields = Bugzilla->active_custom_fields;
foreach my $field (@custom_fields) {
  my $fname = $field->name;
  if (should_set($fname, 1)) {
    $set_all_fields{$fname} = [$cgi->param($fname)];
  }
}

# BMO - add user_match_fields.  it's important to source from input_params
# instead of $cgi->param to ensure we get the correct value.
foreach my $field (keys %$user_match_fields) {
  next if exists $set_all_fields{$field};
  next unless should_set($field, 1);
  $set_all_fields{$field} = Bugzilla->input_params->{$field} // [];
}

# We are going to alter the list of removed groups, so we keep a copy here.
my @unchecked_groups = @$removed_groups;
foreach my $b (@bug_objects) {

  # Don't blindly ask to remove unchecked groups available in the UI.
  # A group can be already unchecked, and the user didn't try to remove it.
  # In this case, we don't want remove_group() to complain.
  my @remove_groups;
  foreach my $g (@{$b->groups_in}) {
    push(@remove_groups, $g->name) if grep { $_ eq $g->name } @unchecked_groups;
  }
  local $set_all_fields{groups}->{remove} = \@remove_groups;
  my $ok = eval {
    $b->set_all(\%set_all_fields);
    1;
  };
  unless ($ok) {
    my $error = $@;
    if (blessed $error && $error->isa('Bugzilla::Error::Template')) {
      print $cgi->header();
      $template->process($error->file, $error->vars);
      exit;
    }
    else {
      die $error;
    }
  }
}

# Flags should be set AFTER the bug has been moved into another
# product/component. The structure of flags code doesn't currently
# allow them to be set using set_all.
foreach my $bug (@bug_objects) {
  my ($flags, $new_flags)
    = Bugzilla::Flag->extract_flags_from_cgi($bug, undef, $vars);
  $bug->set_flags($flags, $new_flags);
}

##############################
# Do Actual Database Updates #
##############################
my @all_sent_changes;
foreach my $bug (@bug_objects) {
  my $changes = $bug->update();

  if ($changes->{'bug_status'}) {
    my $new_status = $changes->{'bug_status'}->[1];

    # We may have zeroed the remaining time, if we moved into a closed
    # status, so we should inform the user about that.
    if (!is_open_state($new_status) && $changes->{'remaining_time'}) {
      $vars->{'message'} = "remaining_time_zeroed" if Bugzilla->user->is_timetracker;
    }
  }

  push @all_sent_changes, $bug->send_changes($changes);
}

# Delete the session token used for the mass-change.
delete_token($token) unless $cgi->param('id');

if (Bugzilla->usage_mode != USAGE_MODE_EMAIL) {
  if ($action eq 'next_bug' or $action eq 'same_bug') {
    # We strip the sent changes to just the necessary parameters so that they can
    # be saved in the session flash.
    my @saved_sent_changes;
    foreach my $sent_changes (@all_sent_changes) {
      foreach my $sent_change (@$sent_changes) {
        my $saved_sent_change = {
          id => $sent_change->{params}->{id},
          type => $sent_change->{params}->{type},
          recipient_count => scalar @{$sent_change->{sent_bugmail}->{sent}},
        };
        push @saved_sent_changes, $saved_sent_change;
      }
    }

    $C->flash(last_sent_changes => \@saved_sent_changes);

    # Redirect to show_bug.cgi.
    # $bug_id will be the same bug or the next bug due to checks earlier in this file.
    # An undefined $bug_id (in the case of $action = 'nothing') will still redirect to
    # show_bug.cgi which will prompt for a bug. This allows mass bug updates to still see
    # the result of what changed/emails sent.
    my $bug_id = $vars->{bug} ? $vars->{bug}->id : undef;
    my $redirect_url = Bugzilla->localconfig->urlbase . "show_bug.cgi?id=$bug_id";
    $C->redirect_to($redirect_url);
    exit;
  }
  else { # Handle $action = 'nothing' or mass bug update case.
    print $cgi->header();

    foreach my $sent_changes (@all_sent_changes) {
      foreach my $sent_change (@$sent_changes) {
        my $params       = $sent_change->{params};
        my $recipient_count = scalar @{$sent_change->{sent_bugmail}->{sent}};
        $vars->{$_} = $params->{$_} foreach keys %$params;
        $vars->{'recipient_count'} = $recipient_count;
        $template->process("bug/process/results.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        $vars->{'header_done'} = 1;
      }
    }

    # End the response page.
    $template->process("bug/navigate.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    $template->process("global/footer.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
  }
}
1;
