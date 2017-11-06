#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla SecureMail Extension
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by Mozilla are Copyright (C) 2008 Mozilla Foundation.
# All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::SecureMail;
use strict;
use warnings;
use 5.10.1;
use base qw(Bugzilla::Extension);

use Bugzilla::Attachment;
use Bugzilla::Comment;
use Bugzilla::Group;
use Bugzilla::Object;
use Bugzilla::User;
use Bugzilla::Util qw(trim trick_taint is_7bit_clean);
use Bugzilla::Error;
use Bugzilla::Mailer;

use Crypt::OpenPGP::Armour;
use Crypt::SMIME;
use Email::MIME::ContentType qw(parse_content_type);
use Encode;
use HTML::Tree;
use List::MoreUtils qw(any none);
use Mail::GPG;
use MIME::Parser;
use GnuPG::Interface;
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);

our $VERSION = '0.5';

use constant SECURE_NONE => 0;
use constant SECURE_BODY => 1;
use constant SECURE_ALL  => 2;

##############################################################################
# Creating new columns
#
# secure_mail boolean in the 'groups' table - whether to send secure mail
# public_key text in the 'profiles' table - stores public key
##############################################################################
sub install_update_db {
    my ($self, $args) = @_;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('groups', 'secure_mail',
                        {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 0});
    $dbh->bz_add_column('profiles', 'public_key', { TYPE => 'LONGTEXT' });
    $dbh->bz_add_column( 'profiles', 'override_test',
                        {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 0} );

    return;
}

##############################################################################
# Maintaining new columns
##############################################################################

BEGIN {
    *Bugzilla::Group::secure_mail  = \&_group_secure_mail;
    *Bugzilla::User::public_key    = \&_user_public_key;
    *Bugzilla::User::override_test = \&_user_override_test;
    *Bugzilla::User::delete_key    = \&_delete_key;
    *Bugzilla::User::add_key       = \&_add_key;
}


sub config_add_panels {
    my($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{SecureMail} = "Bugzilla::Extension::SecureMail::Params";

    return;
}

sub _group_secure_mail { return $_[0]->{'secure_mail'}; }

# We want to lazy-load the public_key.
sub _user_public_key {
    my $self = shift;
    if (!exists $self->{public_key}) {
        ($self->{public_key}) = Bugzilla->dbh->selectrow_array(
            "SELECT public_key FROM profiles WHERE userid = ?",
            undef,
            $self->id
        );
    }
    return $self->{public_key};
}

# We want to lazy-load override_test.
sub _user_override_test {
    my $self = shift;
    if (!exists $self->{override_test}) {
        ($self->{override_test}) = Bugzilla->dbh->selectrow_array(
            "SELECT override_test FROM profiles WHERE userid = ?",
            undef,
            $self->id
        );
    }
    return $self->{override_test};
}
# Make sure generic functions know about the additional fields in the user
# and group objects.
sub object_columns {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $columns = $args->{'columns'};

    if ($class->isa('Bugzilla::Group')) {
        push(@$columns, 'secure_mail');
    }

    return;
}

# Plug appropriate validators so we can check the validity of the two
# fields created by this extension, when new values are submitted.
sub object_validators {
    my ($self, $args) = @_;
    my %args = %{ $args };
    my ($invocant, $validators) = @args{qw(class validators)};

    if ($invocant->isa('Bugzilla::Group')) {
        $validators->{'secure_mail'} = \&Bugzilla::Object::check_boolean;
    }
    elsif ($invocant->isa('Bugzilla::User')) {
        $validators->{'public_key'} = sub {
            my ($self, $value) = @_;
            $value = trim($value) || '';

            return $value if $value eq '';

            if ($value =~ /PUBLIC KEY/) {
                # PGP keys must be ASCII-armoured.
                if (!Crypt::OpenPGP::Armour->unarmour($value)) {
                    ThrowUserError('securemail_invalid_key',
                                   { errstr => Crypt::OpenPGP::Armour->errstr });
                }
            }
            elsif ($value =~ /BEGIN CERTIFICATE/) {
                # S/MIME Keys must be in PEM format (Base64-encoded X.509)
                #
                # Crypt::SMIME seems not to like tainted values - it claims
                # they aren't scalars!
                trick_taint($value);

                my $smime = Crypt::SMIME->new();
                eval {
                    $smime->setPublicKey([$value]);
                };
                if ($@) {
                    ThrowUserError('securemail_invalid_key',
                                   { errstr => $@ });
                }
            }
            else {
                ThrowUserError('securemail_invalid_key');
            }

            return $value;
        };
        $validators->{'override_test'} = sub {
            my ($self, $value) = @_;
            $value = $value ? 1 : 0;
            return $value;
        };
    }

    return;
}

# When creating a 'group' object, set up the secure_mail field appropriately.
sub object_before_create {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    my $params = $args->{'params'};

    if ($class->isa('Bugzilla::Group')) {
        $params->{secure_mail} = Bugzilla->cgi->param('secure_mail');
    }

    return;
}

# On update, make sure the updating process knows about our new columns.
sub object_update_columns {
    my ($self, $args) = @_;
    my $object  = $args->{'object'};
    my $columns = $args->{'columns'};

    if ($object->isa('Bugzilla::Group')) {
        # This seems like a convenient moment to extract this value...
        $object->set('secure_mail', Bugzilla->cgi->param('secure_mail'));

        push(@$columns, 'secure_mail');
    }
    elsif ($object->isa('Bugzilla::User')) {
        push(@$columns, 'public_key');
        push(@$columns, 'override_test');
    }

    return;
}

# Handle the setting and changing of the public key.
sub user_preferences {
    my ($self, $args) = @_;
    my $tab     = $args->{'current_tab'};
    my $save    = $args->{'save_changes'};
    my $handled = $args->{'handled'};
    my $vars    = $args->{'vars'};
    my $params  = Bugzilla->input_params;

    return unless $tab eq 'securemail';

    # Create a new user object so we don't mess with the main one, as we
    # don't know where it's been...
    my $user = new Bugzilla::User(Bugzilla->user->id);

    if ($save) {
        $user->set('public_key', $params->{'public_key'});
        $user->set('override_test', $params->{'override_test'});
        $user->update();
        $user->delete_key();
        # Send user a test email
        if ($user->public_key) {
            $user->add_key($user);
            _send_test_email($user);
            $vars->{'test_email_sent'} = 1;
        }
    }

    $vars->{'public_key'} = $user->public_key;
    $vars->{'override_test'} = $user->override_test;

    # Set the 'handled' scalar reference to true so that the caller
    # knows the panel name is valid and that an extension took care of it.
    $$handled = 1;

    return;
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    # Bug dependency emails contain the subject of the dependent bug
    # right before the diffs when a status has gone from open/closed
    # or closed/open. We need to sanitize the subject of change.blocker
    # similar to how we do referenced bugs
    return unless
        $file eq 'email/bugmail.html.tmpl'
        || $file eq 'email/bugmail.txt.tmpl';

    if (defined $vars->{diffs}) {
        foreach my $change (@{ $vars->{diffs} }) {
            next if !defined $change->{blocker};
            if (any {$_->secure_mail == 1} @{ $change->{blocker}->groups_in }) {
                $change->{blocker}->{short_desc} = "(Secure bug)";
            }
        }
    }

    return;
}

sub _send_test_email {
    my ($user) = @_;
    my $template = Bugzilla->template_inner($user->settings->{'lang'}->{'value'});

    my $vars = {
        to_user => $user->email,
    };

    my $msg = "";
    $template->process("account/email/securemail-test.txt.tmpl", $vars, \$msg)
        || ThrowTemplateError($template->error());

    MessageToMTA($msg);

    return;
}

##############################################################################
# Encrypting the email
##############################################################################
sub mailer_before_send {
    my ($self, $args) = @_;

    my $email = $args->{'email'};
    my $body  = $email->body;

    # REDHAT EXTENSION 1284377 BEGIN
    my $has_status = defined($email->header('X-Bugzilla-Status'));
    my $has_type = defined($email->header('X-Bugzilla-Type'));

    # Decide whether to make secure.
    # This is a bit of a hack; it would be nice if it were more clear
    # what sort a particular email is.
    my $is_bugmail      = ($has_status && $email->header('X-Bugzilla-Status'))
                           || ($has_type && ($email->header('X-Bugzilla-Type') eq 'request'));
    my $is_passwordmail = !$is_bugmail && ($body =~ /cfmpw.*cxlpw/s);
    my $is_test_email   = $has_type && ($email->header('X-Bugzilla-Type') =~ /securemail-test/ ? 1 : 0);
    my $is_whine_email  = $has_type && ($email->header('X-Bugzilla-Type') eq 'whine' ? 1 : 0);
    my $encrypt_header  = $email->header('X-Bugzilla-Encrypt') ? 1 : 0;
    # REDHAT EXTENSION 1284377 END

    if ($is_bugmail
        || $is_passwordmail
        || $is_test_email
        || $is_whine_email
        || $encrypt_header
    ) {
        # Convert the email's To address into a User object
        my $login = $email->header('To');
        my $emailsuffix = Bugzilla->params->{'emailsuffix'};
        $login =~ s/$emailsuffix$//;
        my $user = new Bugzilla::User({ name => $login });

        # Default to secure. (Of course, this means if this extension has a
        # bug, lots of people are going to get bugmail falsely claiming their
        # bugs are secure and they need to add a key...)
        my $make_secure = SECURE_ALL;

        if ($is_bugmail) {
            # This is also a bit of a hack, but there's no header with the
            # bug ID in. So we take the first number in the subject.
            my ($bug_id) = ($email->header('Subject') =~ /\[\D+(\d+)\]/);
            my $bug = new Bugzilla::Bug($bug_id);
            if (!_should_secure_bug($bug)) {
                $make_secure = SECURE_NONE;
            }
            # If the insider group has securemail enabled..
            my $insider_group = Bugzilla::Group->new({ name => Bugzilla->params->{'insidergroup'} });
            if ($insider_group
                && $insider_group->secure_mail == 1
                && $make_secure == SECURE_NONE)
            {
                my $comment_is_private = Bugzilla->dbh->selectcol_arrayref(
                    "SELECT isprivate FROM longdescs WHERE bug_id=? ORDER BY bug_when",
                    undef, $bug_id);
                # Encrypt if there are private comments on an otherwise public bug
                while ($body =~ /[\r\n]--- Comment #(\d+)/g) {
                    my $comment_number = $1;
                    if ($comment_number && $comment_is_private->[$comment_number]) {
                        $make_secure = SECURE_BODY;
                        last;
                    }
                }
                # Encrypt if updating a private attachment without a comment
                if ($email->header('X-Bugzilla-Changed-Fields')
                    && $email->header('X-Bugzilla-Changed-Fields') =~ /Attachment #(\d+)/)
                {
                    my $attachment = Bugzilla::Attachment->new($1);
                    if ($attachment && $attachment->isprivate) {
                        $make_secure = SECURE_BODY;
                    }
                }
            }
        }
        elsif ($is_passwordmail) {
            # Mail is made unsecure only if the user does not have a public
            # key and is not in any security groups. So specifying a public
            # key OR being in a security group means the mail is kept secure
            # (but, as noted above, the check is the other way around because
            # we default to secure).
            if ($user &&
                !$user->public_key &&
                none {$_->secure_mail == 1} @{ $user->groups })
            {
                $make_secure = SECURE_NONE;
            }
        }
        elsif ($is_whine_email) {
            # When a whine email has one or more secure bugs in the body, then
            # encrypt the entire email body. Subject can be left alone as it
            # comes from the whine settings.
            $make_secure = _should_secure_whine($email) ? SECURE_BODY : SECURE_NONE;
        }
        elsif ($encrypt_header) {
            # Templates or code may set the X-Bugzilla-Encrypt header to
            # trigger encryption of emails. Remove that header from the email.
            $email->header_set('X-Bugzilla-Encrypt');
        }

        # If finding the user fails for some reason, but we determine we
        # should be encrypting, we want to make the mail safe. An empty key
        # does that.
        my $public_key = $user ? $user->public_key : '';

        # Check if the new bugmail prefix should be added to the subject.
        my $add_new = ($email->header('X-Bugzilla-Type') eq 'new' &&
                       $user &&
                       $user->settings->{'bugmail_new_prefix'}->{'value'} eq 'on') ? 1 : 0;

        if ($make_secure == SECURE_NONE) {
            # Filter the bug_links in HTML email in case the bugs the links
            # point are "secured" bugs and the user may not be able to see 
            # the summaries.
            _filter_bug_links($email);
        }
        else {
            _make_secure($email, $public_key, $is_bugmail && $make_secure == SECURE_ALL, $add_new);
        }
    }

    return;
}

# Custom hook for bugzilla.mozilla.org (see bug 752400)
sub bugmail_referenced_bugs {
    my ($self, $args) = @_;
    # Sanitise subjects of referenced bugs.
    my $referenced_bugs = $args->{'referenced_bugs'};
    # No need to sanitise subjects if the entire email will be secured.
    return if _should_secure_bug($args->{'updated_bug'});
    # Replace the subject if required
    foreach my $ref (@$referenced_bugs) {
        if (any {$_->secure_mail == 1} @{ $ref->{'bug'}->groups_in }) {
            $ref->{'short_desc'} = "(Secure bug)";
        }
    }

    return;
}

sub _should_secure_bug {
    my ($bug) = @_;
    # If there's a problem with the bug, err on the side of caution and mark it
    # as secure.
    return
        !$bug
        || $bug->{'error'}
        || any {$_->secure_mail == 1} @{ $bug->groups_in };
}

sub _should_secure_whine {
    my ($email) = @_;
    my $should_secure = 0;
    $email->walk_parts(sub {
        my $part = shift;
        my $content_type = $part->content_type;
        return if !$content_type || $content_type !~ /^text\/plain/;
        my $body = $part->body;
        my @bugids = $body =~ /Bug (\d+):/g;
        foreach my $id (@bugids) {
            $id = trim($id);
            next if !$id;
            my $bug = new Bugzilla::Bug($id);
            if ($bug && _should_secure_bug($bug)) {
                $should_secure = 1;
                last;
            }
        }
    });
    return $should_secure ? 1 : 0;
}

=head2 key_dir

Returns the full path to the directory the Pubic keys are kept in.

=cut

sub key_dir {
    return catdir(Bugzilla->params->{gpg_home_dir},"keys");
}

=head2 key_path

Returns the full path to the supplied mail addresses Public key file.

=cut

sub key_path {
    my $login = shift;
    return catfile(key_dir(), "$login.asc");
}

=head2 get_gpg

Returns refs to a GnuPG::Interface object and a GnuPG::Handles object.

=cut

sub get_gpg {
    my $gpg = GnuPG::Interface->new();
    $gpg->options->hash_init(
        armor   => 1,
        homedir => Bugzilla->params->{gpg_home_dir},
        verbose => 1,
    );
    $gpg->hash_init(
        call    => Bugzilla->params->{gpg_cmd},
    );

    my $handles = GnuPG::Handles->new(
        stdin  => IO::Handle->new(),
        stdout => IO::Handle->new(),
        stderr => IO::Handle->new(),
        status => IO::Handle->new(),
    );

    return($gpg, $handles);
}

=head2 close_handles

Closes all IOs for the supplied GnuPG::Handles object.

=cut

sub close_handles {
    my $handles = shift;

    my $out = $handles->{'stdout'};
    my $err = $handles->{'stderr'};
    my $status = $handles->{'status'};
    my $in = $handles->{'stdin'};

    close $in     if($in);
    close $out    if($out);
    close $status if($status);
    close $err    if($err);

    return;
}

sub _delete_key {
    my $user = shift;
    my $login = $user->login;
    my $key_path = key_path($login);

#    unlink $key_path if(-f $key_path);
 Bugzilla->logger->info("\n\nexists $key_path") if(-f $key_path);
    my ($gpg, $handles) = get_gpg();
    $gpg->options->meta_interactive( 0 );

    $gpg->wrap_call(commands => ['--delete-keys', '--yes'], handles => $handles, command_args => [$login] );

    my $out = $handles->{'stdout'};
    my $err = $handles->{'stderr'};
    my $status = $handles->{'status'};
    my $in = $handles->{'stdin'};
    my @out = <$out>;
    my @err = <$err>;
    my @sta = <$status>;
    if(@err) {
        my $errstr = join("\n", (@out, @err, @sta));
        if($errstr !~ /not found/ig &&
           $errstr !~ /no such file or directory/ig &&
           $errstr !~ /^gpg: WARNING: unsafe ownership on homedir/ &&
           $errstr !~ /^gpg: using PGP trust model/) {
            ThrowCodeError('securemail_cant_open_keyfile', {filename => $key_path, errstr => $errstr});
        }
    }
    close_handles($handles);

    unlink $key_path if(-f $key_path);

    return;
}

sub _add_key {
    my $user = shift;

    my $key = $user->public_key;
    my $login = $user->login;

    my $key_path = key_path($login);
    unless(-e key_dir()) {
        eval {
            mkpath(key_dir());
        };
        ThrowCodeError('securemail_cant_create_dir', {dirname => key_dir(), errstr => $@}) if($@);
    }

    my $OUT;
    open($OUT, ">", $key_path) || ThrowCodeError('securemail_cant_open_keyfile', {filename => $key_path, errstr => $!});
    print $OUT $key;
    close $OUT;

    my ($gpg, $handles) = get_gpg();
    $gpg->options->meta_interactive( 0 );
    $gpg->import_keys(handles => $handles, command_args => [$key_path] );

    my $out = $handles->{'stdout'};
    my $err = $handles->{'stderr'};
    my $status = $handles->{'status'};
    my @out = <$out>;
    my @err = <$err>;
    my @sta = <$status>;

    Bugzilla->logger->debug(join("\n", (@out, @err, @sta))) if(@err);

    close_handles($handles);

    return;
}

sub _make_secure {
    my ($email, $key, $sanitise_subject, $add_new) = @_;

    # Add header showing this email has been secured
    $email->header_set('X-Bugzilla-Secure-Email', 'Yes');

    my $subject = $email->header('Subject');
    my ($bug_id) = $subject =~ /\[\D+(\d+)\]/;

    my $key_type = 0;
    if ($key && $key =~ /PUBLIC KEY/) {
        $key_type = 'PGP';
    }
    elsif ($key && $key =~ /BEGIN CERTIFICATE/) {
        $key_type = 'S/MIME';
    }

    if( $key_type eq 'PGP' ) {
        ##################
        # PGP Encryption #
        ##################
        my $to     = $email->header('To');

        my ($gpg, $handles) = get_gpg();
        $gpg->options->meta_interactive(0);
        my @res = $gpg->get_public_keys();
        my $key_path = key_path($to);
        close_handles($handles);

        unless( -f $key_path ) {
            my $user = new Bugzilla::User( { name => $to } );
            $user->add_key();
        }

        my $mg = Mail::GPG->new(
            gpg_call        => Bugzilla->params->{gpg_cmd},
            gnupg_hash_init => {
                always_trust => 1,
                homedir      => Bugzilla->params->{gpg_home_dir},
            },
        );
        my $txt    = $email->as_string();
        my $entity = Mail::GPG->parse( mail_sref => \$txt );

        $email->parts_set( [] );

        my $encrypted_entity;
        eval {
            $encrypted_entity = $mg->mime_encrypt(
                entity     => $entity,
                recipients => [$to],
            );
        };

        if (!$@) {
            $email->charset_set(undef);
            $email->encoding_set(undef);
            my @parts;
            foreach my $part ( $encrypted_entity->parts ) {
                my $bh       = $part->bodyhandle;
                my $head     = $part->head;
                my $new_part = Email::MIME->create(
                    attributes => {
                        content_type => $head->mime_type,
                        disposition => 'inline',
                    },
                    body => $bh->as_string,
                );
                push( @parts, $new_part );
            }

            $email->parts_set( \@parts );
            $email->header_str_set('Content-Type', $encrypted_entity->head->get('content-type'));
            $email->boundary_set( $encrypted_entity->head->multipart_boundary());

        }
        else {
            Bugzilla->logger->error($@);
            $email->body_set( 'Error during Encryption: ' . $@ );
        }

    }

    elsif ($key_type eq 'S/MIME') {
        #####################
        # S/MIME Encryption #
        #####################

        $email->walk_parts(\&_fix_encoding);

        if ($sanitise_subject) {
            $email->walk_parts(sub { _insert_subject($_[0], $subject) });
        }

        my $smime = Crypt::SMIME->new();
        my $encrypted;

        eval {
            $smime->setPublicKey([$key]);
            $encrypted = $smime->encrypt($email->as_string());
        };
        if (!$@) {
            # We can't replace the Email::MIME object, so we have to swap
            # out its component parts.
            my $enc_obj = new Email::MIME($encrypted);
            $email->header_obj_set($enc_obj->header_obj());
            $email->parts_set([]);
            $email->body_set($enc_obj->body());
            $email->content_type_set('application/pkcs7-mime');
            $email->charset_set('UTF-8') if Bugzilla->params->{'utf8'};
        }
        else {
            $email->body_set('Error during Encryption: ' . $@);
        }

    }
    else {
        # No encryption key provided; send a generic, safe email.
        my $template = Bugzilla->template;
        my $message;
        my $vars = {
          'urlbase'    => Bugzilla->localconfig->{urlbase},
          'bug_id'     => $bug_id,
          'maintainer' => Bugzilla->params->{'maintainer'}
        };

        $template->process('account/email/encryption-required.txt.tmpl',
                           $vars, \$message)
          || ThrowTemplateError($template->error());

        $email->parts_set([]);
        $email->content_type_set('text/plain');
        $email->body_set($message);
    }

    if ($sanitise_subject) {
        # This is designed to still work if the admin changes the word
        # 'bug' to something else. However, it could break if they change
        # the format of the subject line in another way.
        my $new = $add_new ? ' New:' : '';
        my $product = $email->header('X-Bugzilla-Product');
        my $component = $email->header('X-Bugzilla-Component');
        # Note: the $bug_id is required within the parentheses in order to keep
        # gmail's threading algorithm happy.
        $subject =~ s/($bug_id\])\s+(.*)$/$1$new (Secure bug $bug_id in $product :: $component)/;
        $email->header_set('Subject', $subject);
    }

    return;
}

sub _pgp_encrypt {
    my ($pgp, $text) = @_;
    # "@" matches every key in the public key ring, which is fine,
    # because there's only one key in our keyring.
    #
    # We use the CAST5 cipher because the Rijndael (AES) module doesn't
    # like us for some reason I don't have time to debug fully.
    # ("key must be an untainted string scalar")
    my $encrypted = $pgp->encrypt(Data       => $text,
                                  Recipients => "@",
                                  Cipher     => 'CAST5',
                                  Armour     => 1);
    if (!defined $encrypted) {
        return 'Error during Encryption: ' . $pgp->errstr;
    }
    return $encrypted;
}

# Insert the subject into the part's body, as the subject of the message will
# be sanitised.
# XXX this incorrectly assumes all parts of the message are the body
# we should only alter parts who's parent is multipart/alternative
sub _insert_subject {
    my ($part, $subject) = @_;
    my $content_type = $part->content_type or return;
    if ($content_type =~ /^text\/plain/) {
        if (!is_7bit_clean($subject)) {
            $part->encoding_set('quoted-printable');
        }
        $part->body_str_set("Subject: $subject\015\012\015\012" . $part->body_str);
    }
    elsif ($content_type =~ /^text\/html/) {
        my $tree = HTML::Tree->new->parse_content($part->body_str);
        my $body = $tree->look_down(qw(_tag body));
        $body->unshift_content(['div', "Subject: $subject"], ['br']);
        _set_body_from_tree($part, $tree);
    }

    return;
}

sub _fix_encoding {
    my $part = shift;

    # don't touch the top-level part of multi-part mail
    return if $part->parts > 1;

    # nothing to do if the part already has a charset
    my $ct = parse_content_type($part->content_type);
    my $charset = $ct->{attributes}{charset}
        ? $ct->{attributes}{charset}
        : '';
    return unless !$charset || $charset eq 'us-ascii';

    if (Bugzilla->params->{utf8}) {
        $part->charset_set('UTF-8');
        my $raw = $part->body_raw;
        if (utf8::is_utf8($raw)) {
            utf8::encode($raw);
            $part->body_set($raw);
        }
    }
    $part->encoding_set('quoted-printable');

    return;
}

sub _filter_bug_links {
    my ($email) = @_;
    $email->walk_parts(sub {
        my $part = shift;
        _fix_encoding($part);
        my $content_type = $part->content_type;
        return if !$content_type || $content_type !~ /text\/html/;
        my $tree = HTML::Tree->new->parse_content($part->body_str);
        my @links = $tree->look_down( _tag  => q{a}, class => qr/bz_bug_link/ );
        my $updated = 0;
        foreach my $link (@links) {
            my $href = $link->attr('href');
            my ($bug_id) = $href =~ /\Qshow_bug.cgi?id=\E(\d+)/;
            my $bug = new Bugzilla::Bug($bug_id);
            if ($bug && _should_secure_bug($bug)) {
                $link->attr('title', '(secure bug)');
                $link->attr('class', 'bz_bug_link');
                $updated = 1;
            }
        }
        if ($updated) {
            _set_body_from_tree($part, $tree);
        }

        return;
    });

    return;
}

sub _set_body_from_tree {
    my ($part, $tree) = @_;
    $part->body_set($tree->as_HTML);
    $part->charset_set('UTF-8') if Bugzilla->params->{'utf8'};
    $part->encoding_set('quoted-printable');

    return;
}

__PACKAGE__->NAME;
