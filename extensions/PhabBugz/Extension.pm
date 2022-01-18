# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Mailer qw(MessageToMTA);
use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::User;
use Bugzilla::Extension::PhabBugz::Util qw(request);

use Try::Tiny;

our $VERSION = '0.01';

sub template_before_process {
  my ($self, $args) = @_;
  my $file = $args->{'file'};
  my $vars = $args->{'vars'};

  return unless Bugzilla->user->id;
  return unless Bugzilla->params->{phabricator_enabled};
  return unless Bugzilla->params->{phabricator_base_uri};
  return unless $file =~ /bug_modal\/(header|edit).html.tmpl$/;

  if (my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'}) {
    my $has_revisions = 0;
    my $active_revision_count = 0;
    foreach my $attachment (@{$bug->attachments}) {
      next if $attachment->contenttype ne PHAB_CONTENT_TYPE;
      $active_revision_count++ if !$attachment->isobsolete;
      $has_revisions = 1;
    }
    $vars->{phabricator_revisions} = $has_revisions;
    $vars->{phabricator_active_revision_count} = $active_revision_count;
  }
}

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{PhabBugz} = "Bugzilla::Extension::PhabBugz::Config";
}

sub webservice {
  my ($self, $args) = @_;
  $args->{dispatch}->{PhabBugz} = "Bugzilla::Extension::PhabBugz::WebService";
}

sub object_end_of_update {
  my ($self,   $args)    = @_;
  my ($object, $changes) = @$args{qw(object changes)};
  my $params = Bugzilla->params;

  next
    if !$params->{phabricator_enabled}
    || !$object->isa('Bugzilla::User')
    || !$changes
    || !$changes->{disabledtext};

  my $user = $object;

  my $orig_error_mode = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_DIE);

  try {
    my $phab_user
      = Bugzilla::Extension::PhabBugz::User->new_from_query({ids => [$user->id]});
    return if !$phab_user;
    $phab_user->set_user_enabled_status($user->is_enabled);
  }
  catch {
    # We're sending to the maintainer, who may be not a Bugzilla
    # account, but just an email address. So we use the
    # installation's default language for sending the email.
    my $default_settings = Bugzilla::User::Setting::get_defaults();
    my $template
      = Bugzilla->template_inner($default_settings->{lang}->{default_value});
    my $vars = {user => $user, error => $_};
    my $message;
    $template->process('email/phab_enabled_status.txt.tmpl', $vars, \$message)
      || ThrowTemplateError($template->error);
    MessageToMTA($message);

    WARN('ERROR: Error updating Phabricator user status for Bugzilla user '
        . $user->login);
  };

  Bugzilla->error_mode($orig_error_mode);
}

#
# installation/config hooks
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{'schema'}->{'phabbugz'} = {
    FIELDS => [
      id    => {TYPE => 'INTSERIAL',    NOTNULL => 1, PRIMARYKEY => 1,},
      name  => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
      value => {TYPE => 'MEDIUMTEXT',   NOTNULL => 1}
    ],
    INDEXES => [phabbugz_idx => {FIELDS => ['name'], TYPE => 'UNIQUE',},],
  };
}

sub install_filesystem {
  my ($self, $args) = @_;
  my $files = $args->{'files'};

  my $extensionsdir = bz_locations()->{'extensionsdir'};
  my $scriptname    = $extensionsdir . "/PhabBugz/bin/phabbugz_feed.pl";

  $files->{$scriptname} = {perms => Bugzilla::Install::Filesystem::WS_EXECUTE};
}

sub merge_users_before {
  my ($self, $args) = @_;
  my $old_id = $args->{old_id};
  my $force  = $args->{force};

  return if $force;

  my $result = request('bugzilla.account.search', {ids => [$old_id]});

  foreach my $user (@{$result->{result}}) {
    next if !$user->{phid};
    ThrowUserError('phabricator_merge_user_abort',
      {user => Bugzilla::User->new({id => $old_id, cache => 1})});
  }
}

__PACKAGE__->NAME;
