# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment;

use 5.10.1;
use strict;
use warnings;

=head1 NAME

Bugzilla::Attachment - Bugzilla attachment class.

=head1 SYNOPSIS

  use Bugzilla::Attachment;

  # Get the attachment with the given ID.
  my $attachment = new Bugzilla::Attachment($attach_id);

  # Get the attachments with the given IDs.
  my $attachments = Bugzilla::Attachment->new_from_list($attach_ids);

=head1 DESCRIPTION

Attachment.pm represents an attachment object. It is an implementation
of L<Bugzilla::Object>, and thus provides all methods that
L<Bugzilla::Object> provides.

The methods that are specific to C<Bugzilla::Attachment> are listed
below.

=cut

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Flag;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Field;
use Bugzilla::Hook;

use File::Copy;
use List::Util qw(max);
use Scalar::Util qw(weaken);
use Storable qw(dclone);

use base qw(Bugzilla::Object);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'attachments';
use constant ID_FIELD   => 'attach_id';
use constant LIST_ORDER => ID_FIELD;
# Attachments are tracked in bugs_activity.
use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;

use constant DB_COLUMNS => qw(
    attach_id
    bug_id
    creation_ts
    description
    filename
    isobsolete
    ispatch
    isprivate
    mimetype
    modification_time
    submitter_id
    attach_size
);

use constant REQUIRED_FIELD_MAP => {
    bug_id => 'bug',
};
use constant EXTRA_REQUIRED_FIELDS => qw(data);

use constant UPDATE_COLUMNS => qw(
    description
    filename
    isobsolete
    ispatch
    isprivate
    mimetype
);

use constant VALIDATORS => {
    bug           => \&_check_bug,
    description   => \&_check_description,
    filename      => \&_check_filename,
    ispatch       => \&Bugzilla::Object::check_boolean,
    isprivate     => \&_check_is_private,
    mimetype      => \&_check_content_type,
};

use constant VALIDATOR_DEPENDENCIES => {
    content_type => ['ispatch'],
    mimetype     => ['ispatch'],
};

use constant UPDATE_VALIDATORS => {
    isobsolete => \&Bugzilla::Object::check_boolean,
};

###############################
####      Accessors      ######
###############################

=pod

=head2 Instance Properties

=over

=item C<bug_id>

the ID of the bug to which the attachment is attached

=back

=cut

sub bug_id {
    return $_[0]->{bug_id};
}

=over

=item C<bug>

the bug object to which the attachment is attached

=back

=cut

sub bug {
    my ($self) = @_;
    require Bugzilla::Bug;
    return $self->{bug} if defined $self->{bug};
    my $bug = $self->{bug} = Bugzilla::Bug->new({ id => $_[0]->bug_id, cache => 1 });
    weaken($self->{bug});
    return $bug;
}

=over

=item C<description>

user-provided text describing the attachment

=back

=cut

sub description {
    return $_[0]->{description};
}

=over

=item C<contenttype>

the attachment's MIME media type

=back

=cut

sub contenttype {
    return $_[0]->{mimetype};
}

=over

=item C<attacher>

the user who attached the attachment

=back

=cut

sub attacher {
    return $_[0]->{attacher}
        //= new Bugzilla::User({ id => $_[0]->{submitter_id}, cache => 1 });
}

=over

=item C<attached>

the date and time on which the attacher attached the attachment

=back

=cut

sub attached {
    return $_[0]->{creation_ts};
}

=over

=item C<modification_time>

the date and time on which the attachment was last modified.

=back

=cut

sub modification_time {
    return $_[0]->{modification_time};
}

=over

=item C<filename>

the name of the file the attacher attached

=back

=cut

sub filename {
    return $_[0]->{filename};
}

=over

=item C<ispatch>

whether or not the attachment is a patch

=back

=cut

sub ispatch {
    return $_[0]->{ispatch};
}

=over

=item C<isobsolete>

whether or not the attachment is obsolete

=back

=cut

sub isobsolete {
    return $_[0]->{isobsolete};
}

=over

=item C<isprivate>

whether or not the attachment is private

=back

=cut

sub isprivate {
    return $_[0]->{isprivate};
}

=over

=item C<is_viewable>

Returns 1 if the attachment has a content-type viewable in this browser.
Note that we don't use $cgi->Accept()'s ability to check if a content-type
matches, because this will return a value even if it's matched by the generic
*/* which most browsers add to the end of their Accept: headers.

=back

=cut

sub is_viewable {
    my $contenttype = $_[0]->contenttype;
    my $cgi = Bugzilla->cgi;

    # We assume we can view all text and image types.
    return 1 if ($contenttype =~ /^(text|image)\//);

    # Modern browsers support PDF as well.
    return 1 if ($contenttype eq 'application/pdf');

    # If it's not one of the above types, we check the Accept: header for any
    # types mentioned explicitly.
    my $accept = join(",", $cgi->Accept());
    return 1 if ($accept =~ /^(.*,)?\Q$contenttype\E(,.*)?$/);

    return 0;
}

=over

=item C<data>

the content of the attachment

=back

=cut

sub data {
    my $self = shift;
    return $self->{data} //= current_storage()->retrieve($self->id);
}

=over

=item C<datasize>

the length (in bytes) of the attachment content

=back

=cut

sub datasize {
    return $_[0]->{attach_size};
}

=over

=item C<flags>

flags that have been set on the attachment

=back

=cut

sub flags {
    # Don't cache it as it must be in sync with ->flag_types.
    return $_[0]->{flags} = [map { @{$_->{flags}} } @{$_[0]->flag_types}];
}

=over

=item C<flag_types>

Return all flag types available for this attachment as well as flags
already set, grouped by flag type.

=back

=cut

sub flag_types {
    my $self = shift;
    return $self->{flag_types} if exists $self->{flag_types};

    my $vars = { target_type  => 'attachment',
                 product_id   => $self->bug->product_id,
                 component_id => $self->bug->component_id,
                 attach_id    => $self->id,
                 active_or_has_flags => $self->bug_id };

    return $self->{flag_types} = Bugzilla::Flag->_flag_types($vars);
}

###############################
####      Validators     ######
###############################

sub set_content_type { $_[0]->set('mimetype', $_[1]); }
sub set_description  { $_[0]->set('description', $_[1]); }
sub set_filename     { $_[0]->set('filename', $_[1]); }
sub set_is_patch     { $_[0]->set('ispatch', $_[1]); }
sub set_is_private   { $_[0]->set('isprivate', $_[1]); }

sub set_is_obsolete  {
    my ($self, $obsolete) = @_;

    my $old = $self->isobsolete;
    $self->set('isobsolete', $obsolete);
    my $new = $self->isobsolete;

    # If the attachment is being marked as obsolete, cancel pending requests.
    if ($new && $old != $new) {
        my @requests = grep { $_->status eq '?' } @{$self->flags};
        return unless scalar @requests;

        my %flag_ids = map { $_->id => 1 } @requests;
        foreach my $flagtype (@{$self->flag_types}) {
            @{$flagtype->{flags}} = grep { !$flag_ids{$_->id} } @{$flagtype->{flags}};
        }
    }
}

sub set_flags {
    my ($self, $flags, $new_flags) = @_;

    Bugzilla::Flag->set_flag($self, $_) foreach (@$flags, @$new_flags);
}

sub _check_bug {
    my ($invocant, $bug) = @_;
    my $user = Bugzilla->user;

    $bug = ref $invocant ? $invocant->bug : $bug;

    $bug || ThrowCodeError('param_required',
                           { function => "$invocant->create", param => 'bug' });

    ($user->can_see_bug($bug->id) && $user->can_edit_product($bug->product_id))
      || ThrowUserError("illegal_attachment_edit_bug", { bug_id => $bug->id });

    return $bug;
}

sub _check_content_type {
    my ($invocant, $content_type, undef, $params) = @_;

    my $is_patch = ref($invocant) ? $invocant->ispatch : $params->{ispatch};
    $content_type = 'text/plain' if $is_patch;
    $content_type = clean_text($content_type);
    # The subsets below cover all existing MIME types and charsets registered by IANA.
    # (MIME type: RFC 2045 section 5.1; charset: RFC 2278 section 3.3)
    my $legal_types = join('|', LEGAL_CONTENT_TYPES);
    if (!$content_type
        || $content_type !~ /^($legal_types)\/[a-z0-9_\-\+\.]+(;\s*charset=[a-z0-9_\-\+]+)?$/i)
    {
        ThrowUserError("invalid_content_type", { contenttype => $content_type });
    }
    trick_taint($content_type);

    return $content_type;
}

sub _check_data {
    my ($invocant, $params) = @_;

    my $data = $params->{data};
    $params->{attach_size} = ref $data ? -s $data : length($data);

    Bugzilla::Hook::process('attachment_process_data', { data       => \$data,
                                                         attributes => $params });

    $params->{attach_size} || ThrowUserError('zero_length_file');
    # Make sure the attachment does not exceed the maximum permitted size.
    if ($params->{attach_size} > Bugzilla->params->{'maxattachmentsize'} * 1024) {
        ThrowUserError('file_too_large', { filesize => sprintf("%.0f", $params->{attach_size}/1024) });
    }

    return $data;
}

sub _check_description {
    my ($invocant, $description) = @_;

    $description = trim($description);
    $description || ThrowUserError('missing_attachment_description');
    return $description;
}

sub _check_filename {
    my ($invocant, $filename) = @_;

    $filename = clean_text($filename);
    if (!$filename) {
        if (ref $invocant) {
            ThrowUserError('filename_not_specified');
        }
        else {
            ThrowUserError('file_not_specified');
        }
   }

    # Remove path info (if any) from the file name.  The browser should do this
    # for us, but some are buggy.  This may not work on Mac file names and could
    # mess up file names with slashes in them, but them's the breaks.  We only
    # use this as a hint to users downloading attachments anyway, so it's not
    # a big deal if it munges incorrectly occasionally.
    $filename =~ s/^.*[\/\\]//;

    # Truncate the filename to 100 characters, counting from the end of the
    # string to make sure we keep the filename extension.
    $filename = substr($filename, -100, 100);
    trick_taint($filename);

    return $filename;
}

sub _check_is_private {
    my ($invocant, $is_private) = @_;

    $is_private = $is_private ? 1 : 0;
    if (((!ref $invocant && $is_private)
         || (ref $invocant && $invocant->isprivate != $is_private))
        && !Bugzilla->user->is_insider) {
        ThrowUserError('user_not_insider');
    }
    return $is_private;
}

=pod

=head2 Class Methods

=over

=item C<get_attachments_by_bug($bug)>

Description: retrieves and returns the attachments the currently logged in
             user can view for the given bug.

Params:     C<$bug> - Bugzilla::Bug object - the bug for which
            to retrieve and return attachments.

Returns:    a reference to an array of attachment objects.

=cut

sub get_attachments_by_bug {
    my ($class, $bug, $vars) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->dbh;

    # By default, private attachments are not accessible, unless the user
    # is in the insider group or submitted the attachment.
    my $and_restriction = '';
    my @values = ($bug->id);

    unless ($user->is_insider) {
        $and_restriction = 'AND (isprivate = 0 OR submitter_id = ?)';
        push(@values, $user->id);
    }

    # BMO - allow loading of just non-obsolete attachments
    if ($vars->{exclude_obsolete}) {
        $and_restriction .= ' AND (isobsolete = 0)';
    }

    my $attach_ids = $dbh->selectcol_arrayref("SELECT attach_id FROM attachments
                                               WHERE bug_id = ? $and_restriction",
                                               undef, @values);

    my $attachments = Bugzilla::Attachment->new_from_list($attach_ids);

    # To avoid $attachment->flags to run SQL queries itself for each
    # attachment listed here, we collect all the data at once and
    # populate $attachment->{flags} ourselves.
    if ($vars->{preload}) {
        # Preload flag types and flags
        my $vars = { target_type  => 'attachment',
                     product_id   => $bug->product_id,
                     component_id => $bug->component_id,
                     attach_id    => $attach_ids };
        my $flag_types = Bugzilla::Flag->_flag_types($vars);

        foreach my $attachment (@$attachments) {
            $attachment->{flag_types} = [];
            my $new_types = dclone($flag_types);
            foreach my $new_type (@$new_types) {
                $new_type->{flags} = [ grep($_->attach_id == $attachment->id,
                                            @{ $new_type->{flags} }) ];
                push(@{ $attachment->{flag_types} }, $new_type);
            }
        }

        # Preload attachers.
        my %user_ids = map { $_->{submitter_id} => 1 } @$attachments;
        my $users = Bugzilla::User->new_from_list([keys %user_ids]);
        my %user_map = map { $_->id => $_ } @$users;
        foreach my $attachment (@$attachments) {
            $attachment->{attacher} = $user_map{$attachment->{submitter_id}};
        }
    }
    return $attachments;
}

=pod

=item C<validate_can_edit>

Description: validates if the user is allowed to view and edit the attachment.
             Only the submitter or someone with editbugs privs can edit it.
             Only the submitter and users in the insider group can view
             private attachments.

Params:      none

Returns:     1 on success, 0 otherwise.

=cut

sub validate_can_edit {
    my $self = shift;
    my $user = Bugzilla->user;

    # The submitter can edit their attachments.
    return 1 if $self->attacher->id == $user->id;

    # Private attachments
    return 0 if $self->isprivate && !$user->is_insider;

    # BMO: if you can edit the bug, then you can also edit any of its attachments
    return 1 if $self->bug->user->{canedit};

    # If you are in editbugs for this product
    return 1 if $user->in_group('editbugs', $self->bug->product_id);

    return 0;
}

=item C<validate_obsolete($bug, $attach_ids)>

Description: validates if attachments the user wants to mark as obsolete
             really belong to the given bug and are not already obsolete.
             Moreover, a user cannot mark an attachment as obsolete if
             he cannot view it (due to restrictions on it).

Params:      $bug - The bug object obsolete attachments should belong to.
             $attach_ids - The list of attachments to mark as obsolete.

Returns:     The list of attachment objects to mark as obsolete.
             Else an error is thrown.

=cut

sub validate_obsolete {
    my ($class, $bug, $list) = @_;

    # Make sure the attachment id is valid and the user has permissions to view
    # the bug to which it is attached. Make sure also that the user can view
    # the attachment itself.
    my @obsolete_attachments;
    foreach my $attachid (@$list) {
        my $vars = {};
        $vars->{'attach_id'} = $attachid;

        detaint_natural($attachid)
          || ThrowCodeError('invalid_attach_id_to_obsolete', $vars);

        # Make sure the attachment exists in the database.
        my $attachment = new Bugzilla::Attachment($attachid)
          || ThrowUserError('invalid_attach_id', $vars);

        # Check that the user can view and edit this attachment.
        $attachment->validate_can_edit
          || ThrowUserError('illegal_attachment_edit', { attach_id => $attachment->id });

        if ($attachment->bug_id != $bug->bug_id) {
            $vars->{'my_bug_id'} = $bug->bug_id;
            ThrowCodeError('mismatched_bug_ids_on_obsolete', $vars);
        }

        next if $attachment->isobsolete;

        push(@obsolete_attachments, $attachment);
    }
    return @obsolete_attachments;
}

###############################
####     Constructors     #####
###############################

=pod

=item C<create>

Description: inserts an attachment into the given bug.

Params:     takes a hashref with the following keys:
            C<bug> - Bugzilla::Bug object - the bug for which to insert
            the attachment.
            C<data> - Either a filehandle pointing to the content of the
            attachment, or the content of the attachment itself.
            C<description> - string - describe what the attachment is about.
            C<filename> - string - the name of the attachment (used by the
            browser when downloading it). If the attachment is a URL, this
            parameter has no effect.
            C<mimetype> - string - a valid MIME type.
            C<creation_ts> - string (optional) - timestamp of the insert
            as returned by SELECT LOCALTIMESTAMP(0).
            C<ispatch> - boolean (optional, default false) - true if the
            attachment is a patch.
            C<isprivate> - boolean (optional, default false) - true if
            the attachment is private.

Returns:    The new attachment object.

=cut

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;

    $class->check_required_create_fields(@_);
    my $params = $class->run_create_validators(@_);

    # Extract everything which is not a valid column name.
    my $bug = delete $params->{bug};
    $params->{bug_id} = $bug->id;
    my $data = delete $params->{data};

    my $attachment = $class->insert_create_data($params);
    $attachment->{bug} = $bug;

    # store attachment data
    if (ref($data)) {
        local $/;
        my $tmp = <$data>;
        close($data);
        $data = $tmp;
    }
    current_storage()->store($attachment->id, $data);

    # Return the new attachment object
    return $attachment;
}

sub run_create_validators {
    my ($class, $params) = @_;

    # Let's validate the attachment content first as it may
    # alter some other attachment attributes.
    $params->{data} = $class->_check_data($params);
    $params = $class->SUPER::run_create_validators($params);

    $params->{creation_ts} ||= Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    $params->{modification_time} = $params->{creation_ts};
    $params->{submitter_id} = Bugzilla->user->id || ThrowCodeError('invalid_user');

    return $params;
}

sub update {
    my $self = shift;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;
    my $timestamp = shift || $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    my ($changes, $old_self) = $self->SUPER::update(@_);

    my ($removed, $added) = Bugzilla::Flag->update_flags($self, $old_self, $timestamp);
    if ($removed || $added) {
        $changes->{'flagtypes.name'} = [$removed, $added];
    }

    # Record changes in the activity table.
    require Bugzilla::Bug;
    foreach my $field (keys %$changes) {
        my $change = $changes->{$field};
        $field = "attachments.$field" unless $field eq "flagtypes.name";
        Bugzilla::Bug::LogActivityEntry($self->bug_id, $field, $change->[0],
            $change->[1], $user->id, $timestamp, undef, $self->id);
    }

    if (scalar(keys %$changes)) {
        $dbh->do('UPDATE attachments SET modification_time = ? WHERE attach_id = ?',
                 undef, ($timestamp, $self->id));
        $dbh->do('UPDATE bugs SET delta_ts = ? WHERE bug_id = ?',
                 undef, ($timestamp, $self->bug_id));
        $self->{modification_time} = $timestamp;
        # because we updated the attachments table after SUPER::update(), we
        # need to ensure the cache is flushed.
        Bugzilla->memcached->clear({ table => 'attachments', id => $self->id });
    }

    Bugzilla::Hook::process('attachment_end_of_update',
        { object => $self, old_object => $old_self, changes => $changes });

    return $changes;
}

=pod

=item C<remove_from_db()>

Description: removes an attachment from the DB.

Params:     none

Returns:    nothing

=back

=cut

sub remove_from_db {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();
    my $flag_ids = $dbh->selectcol_arrayref(
        'SELECT id FROM flags WHERE attach_id = ?', undef, $self->id);
    $dbh->do('DELETE FROM flags WHERE ' . $dbh->sql_in('id', $flag_ids))
        if @$flag_ids;
    $dbh->do('UPDATE attachments SET mimetype = ?, ispatch = ?, isobsolete = ?, attach_size = ?
              WHERE attach_id = ?', undef, ('text/plain', 0, 1, 0, $self->id));
    $dbh->bz_commit_transaction();
    current_storage()->remove($self->id);

    # As we don't call SUPER->remove_from_db we need to manually clear
    # memcached here.
    Bugzilla->memcached->clear({ table => 'attachments', id => $self->id });
    foreach my $flag_id (@$flag_ids) {
        Bugzilla->memcached->clear({ table => 'flags', id => $flag_id });
    }
}

###############################
####       Helpers        #####
###############################

# Extract the content type from the attachment form.
sub get_content_type {
    my $cgi = Bugzilla->cgi;

    return 'text/plain' if ($cgi->param('ispatch') || $cgi->param('attach_text'));

    my $content_type;
    my $method = $cgi->param('contenttypemethod');

    if (!defined $method) {
        ThrowUserError("missing_content_type_method");
    }
    elsif ($method eq 'autodetect') {
        defined $cgi->upload('data') || ThrowUserError('file_not_specified');
        # The user asked us to auto-detect the content type, so use the type
        # specified in the HTTP request headers.
        $content_type =
            $cgi->uploadInfo($cgi->param('data'))->{'Content-Type'};
        $content_type || ThrowUserError("missing_content_type");

        # Set the ispatch flag to 1 if the content type
        # is text/x-diff or text/x-patch
        if ($content_type =~ m{text/x-(?:diff|patch)}) {
            $cgi->param('ispatch', 1);
            $content_type = 'text/plain';
        }

        # Internet Explorer sends image/x-png for PNG images,
        # so convert that to image/png to match other browsers.
        if ($content_type eq 'image/x-png') {
            $content_type = 'image/png';
        }
    }
    elsif ($method eq 'list') {
        # The user selected a content type from the list, so use their
        # selection.
        $content_type = $cgi->param('contenttypeselection');
    }
    elsif ($method eq 'manual') {
        # The user entered a content type manually, so use their entry.
        $content_type = $cgi->param('contenttypeentry');
    }
    else {
        ThrowCodeError("illegal_content_type_method", { contenttypemethod => $method });
    }
    return $content_type;
}

sub current_storage {
    return state $storage //= get_storage_by_name(Bugzilla->params->{attachment_storage});
}

sub get_storage_names {
    require Bugzilla::Config::Attachment;
    foreach my $param (Bugzilla::Config::Attachment->get_param_list) {
        next unless $param->{name} eq 'attachment_storage';
        return @{ $param->{choices} };
    }
    return [];
}

sub get_storage_by_name {
    my ($name) = @_;
    # all options for attachment_storage need to be handled here
    if ($name eq 'database') {
        require Bugzilla::Attachment::Database;
        return Bugzilla::Attachment::Database->new();
    }
    elsif ($name eq 'filesystem') {
        require Bugzilla::Attachment::FileSystem;
        return Bugzilla::Attachment::FileSystem->new();
    }
    elsif ($name eq 's3') {
        require Bugzilla::Attachment::S3;
        return Bugzilla::Attachment::S3->new();
    }
    else {
        return undef;
    }
}

1;
