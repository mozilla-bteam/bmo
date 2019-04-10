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
use Bugzilla::Attachment;
use Bugzilla::BugMail;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Field;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Keyword;
use Bugzilla::Token;
use Bugzilla::Flag;

use List::MoreUtils qw(uniq);
use MIME::Base64 qw(decode_base64);

my $user = Bugzilla->login(LOGIN_REQUIRED);

my $cgi      = Bugzilla->cgi;
my $dbh      = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars     = {};

######################################################################
# Main Script
######################################################################

# redirect to enter_bug if no field is passed.
unless ($cgi->param()) {
  $cgi->base_redirect('enter_bug.cgi');
}

# BMO: Don't allow updating of bugs if disabled
if (Bugzilla->params->{disable_bug_updates}) {
  ThrowErrorPage(
    'bug/process/updates-disabled.html.tmpl',
    'Bug updates are currently disabled.'
  );
}

# Detect if the user already used the same form to submit a bug
my $token = trim($cgi->param('token'));
check_token_data($token, 'create_bug', 'index.cgi');

# do a match on the fields if applicable
# BMO: allow extensions to define custom user fields
my $user_match_fields = {
  'cc'          => {'type' => 'multi'},
  'assigned_to' => {'type' => 'single'},
  'qa_contact'  => {'type' => 'single'},
};
Bugzilla::Hook::process('bug_user_match_fields',
  {fields => $user_match_fields});
Bugzilla::User::match_field($user_match_fields);

if (defined $cgi->param('maketemplate')) {
  $vars->{'url'}        = $cgi->canonicalise_query('token');
  $vars->{'short_desc'} = $cgi->param('short_desc');

  print $cgi->header();
  $template->process("bug/create/make-template.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

umask 0;

# The format of the initial comment can be structured by adding fields to the
# enter_bug template and then referencing them in the comment template.
my $comment;
my $format
  = $template->get_format("bug/create/comment", scalar($cgi->param('format')),
  "txt");
$template->process($format->{'template'}, $vars, \$comment)
  || ThrowTemplateError($template->error());

# Include custom fields editable on bug creation.
my @custom_bug_fields
  = grep { $_->type != FIELD_TYPE_MULTI_SELECT && $_->enter_bug }
  Bugzilla->active_custom_fields;

# Undefined custom fields are ignored to ensure they will get their default
# value (e.g. "---" for custom single select fields).
my @bug_fields = grep { defined $cgi->param($_->name) } @custom_bug_fields;
@bug_fields = map { $_->name } @bug_fields;

push(
  @bug_fields, qw(
    product
    component

    assigned_to
    qa_contact

    alias
    blocked
    comment_is_private
    bug_file_loc
    bug_severity
    bug_status
    bug_type
    dependson
    keywords
    short_desc
    op_sys
    priority
    regressed_by
    regresses
    rep_platform
    version
    target_milestone
    status_whiteboard
    see_also
    estimated_time
    deadline
    )
);
my %bug_params;
foreach my $field (@bug_fields) {
  $bug_params{$field} = $cgi->param($field);
}
foreach my $field (qw(cc groups)) {
  next if !$cgi->should_set($field);
  $bug_params{$field} = [$cgi->param($field)];
}
$bug_params{'comment'} = $comment;

my @multi_selects
  = grep { $_->type == FIELD_TYPE_MULTI_SELECT && $_->enter_bug }
  Bugzilla->active_custom_fields;

foreach my $field (@multi_selects) {
  next if !$cgi->should_set($field->name);
  $bug_params{$field->name} = [$cgi->param($field->name)];
}

# BMO - add user_match_fields.  it's important to source from input_params
# instead of $cgi->param to ensure we get the correct value.
foreach my $field (keys %$user_match_fields) {
  next if exists $bug_params{$field};
  next unless $cgi->should_set($field);
  $bug_params{$field} = Bugzilla->input_params->{$field} // [];
}

my $bug = Bugzilla::Bug->create(\%bug_params);

# Get the bug ID back and delete the token used to create this bug.
my $id = $bug->bug_id;
delete_token($token);

# We do this directly from the DB because $bug->creation_ts has the seconds
# formatted out of it (which should be fixed some day).
my $timestamp
  = $dbh->selectrow_array('SELECT creation_ts FROM bugs WHERE bug_id = ?',
  undef, $id);

# Set Version cookie, but only if the user actually selected
# a version on the page.
if (defined $cgi->param('version')) {
  $cgi->send_cookie(
    -name    => "VERSION-" . $bug->product,
    -value   => $bug->version,
    -expires => "Fri, 01-Jan-2038 00:00:00 GMT"
  );
}

# We don't have to check if the user can see the bug, because a user filing
# a bug can always see it. You can't change reporter_accessible until
# after the bug is filed.

# Add an attachment if requested.
my $data_fh     = $cgi->upload('data');
my $attach_text = $cgi->param('attach_text');
my $data_base64 = $cgi->param('data_base64');

if ($data_fh || $attach_text || $data_base64) {
  $cgi->param('isprivate', $cgi->param('comment_is_private'));

  # Must be called before create() as it may alter $cgi->param('ispatch').
  my $content_type = Bugzilla::Attachment::get_content_type();
  my $attachment;
  my $data;
  my $filename;

  if ($attach_text) {

    # Convert to unix line-endings if pasting a patch
    if (scalar($cgi->param('ispatch'))) {
      $attach_text =~ s/[\012\015]{1,2}/\012/g;
    }
    $data     = $attach_text;
    $filename = "file_$id.txt";
  }
  elsif ($data_base64) {
    $data = decode_base64($data_base64);
    $filename = $cgi->param('filename') || "file_$id";
  }
  else {
    $data = $filename = $data_fh;
  }

  # If the attachment cannot be successfully added to the bug,
  # we notify the user, but we don't interrupt the bug creation process.
  my $error_mode_cache = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_DIE);
  eval {
    $attachment = Bugzilla::Attachment->create({
      bug         => $bug,
      creation_ts => $timestamp,
      data        => $data,
      description => scalar $cgi->param('description'),
      filename    => $filename,
      ispatch     => scalar $cgi->param('ispatch'),
      isprivate   => scalar $cgi->param('isprivate'),
      mimetype    => $content_type,
    });
  };
  Bugzilla->error_mode($error_mode_cache);

  if ($attachment) {

    # Set attachment flags.
    Bugzilla::Hook::process('post_bug_attachment_flags',
      {bug => $bug, attachment => $attachment});
    my ($flags, $new_flags)
      = Bugzilla::Flag->extract_flags_from_cgi($bug, $attachment, $vars,
      SKIP_REQUESTEE_ON_ERROR);
    $attachment->set_flags($flags, $new_flags);
    $attachment->update($timestamp);
    my $comment = $bug->comments->[0];
    $comment->set_all(
      {type => CMT_ATTACHMENT_CREATED, extra_data => $attachment->id});
    $comment->update();
  }
  else {
    $vars->{'message'} = 'attachment_creation_failed';
  }
}

# Set bug_ignored from the hidden field
if (scalar $cgi->param('bug_ignored')) {
  $bug->set_bug_ignored(1);
}

# Set bug flags.
my ($flags, $new_flags)
  = Bugzilla::Flag->extract_flags_from_cgi($bug, undef, $vars,
  SKIP_REQUESTEE_ON_ERROR);
$bug->set_flags($flags, $new_flags);
$bug->update($timestamp);

$vars->{'id'}  = $id;
$vars->{'bug'} = $bug;

Bugzilla::Hook::process('post_bug_after_creation', {vars => $vars});

ThrowCodeError("bug_error", {bug => $bug}) if $bug->error;

my $recipients = {changer => $user};
my $bug_sent = Bugzilla::BugMail::Send($id, $recipients);
$bug_sent->{type} = 'created';
$bug_sent->{id}   = $id;
my @all_mail_results = ($bug_sent);

foreach my $dep (
  map { @{$bug->{$_} || []} } qw(dependson blocked regressed_by regresses)
) {
  my $dep_sent = Bugzilla::BugMail::Send($dep, $recipients);
  $dep_sent->{type} = 'dep';
  $dep_sent->{id}   = $dep;
  push(@all_mail_results, $dep_sent);
}

# Sending emails for any referenced bugs.
foreach my $ref_bug_id (uniq @{$bug->{see_also_changes} || []}) {
  my $ref_sent = Bugzilla::BugMail::Send($ref_bug_id, $recipients);
  $ref_sent->{id} = $ref_bug_id;
  push(@all_mail_results, $ref_sent);
}

$vars->{sentmail} = \@all_mail_results;

$format = $template->get_format("bug/create/created",
  scalar($cgi->param('created-format')), "html");

# don't leak the enter_bug format param to show_bug
$cgi->delete('format');

if ($user->setting('ui_experiments') eq 'on') {
  $C->content_security_policy(SHOW_BUG_MODAL_CSP($bug->id));
}
print $cgi->header();
$template->process($format->{'template'}, $vars)
  || ThrowTemplateError($template->error());

1;
