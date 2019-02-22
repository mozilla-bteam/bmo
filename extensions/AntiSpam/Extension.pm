# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AntiSpam;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Util qw(remote_ip);
use Email::Address;
use Socket;

our $VERSION = '1';

#
# project honeypot integration
#

sub _project_honeypot_blocking {
  my ($self, $api_key, $login) = @_;
  my $ip = remote_ip();
  return unless $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
  my $lookup = "$api_key.$4.$3.$2.$1.dnsbl.httpbl.org";
  return unless my $packed = gethostbyname($lookup);
  my $honeypot = inet_ntoa($packed);
  return unless $honeypot =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
  my ($status, $days, $threat, $type) = ($1, $2, $3, $4);

  return
    if $status != 127 || $threat < Bugzilla->params->{honeypot_threat_threshold};

  Bugzilla->audit(
    sprintf("blocked <%s> from creating %s, honeypot %s", $ip, $login, $honeypot));
  ThrowUserError('account_creation_restricted');
}

sub config_modify_panels {
  my ($self, $args) = @_;
  push @{$args->{panels}->{auth}->{params}},
    {name => 'honeypot_api_key', type => 't', default => '',};
  push @{$args->{panels}->{auth}->{params}},
    {name => 'honeypot_threat_threshold', type => 't', default => '32',};
}

#
# comment blocking
#

sub _comment_blocking {
  my ($self, $params) = @_;
  my $user = Bugzilla->user;
  return if $user->in_group('editbugs');

  my $blocklist = Bugzilla->dbh->selectcol_arrayref(
    'SELECT word FROM antispam_comment_blocklist');
  return unless @$blocklist;

  my $regex = '\b(?:' . join('|', map {quotemeta} @$blocklist) . ')\b';
  if ($params->{thetext} =~ /$regex/i) {
    Bugzilla->audit(sprintf(
      "blocked <%s> %s from commenting, blacklisted phrase",
      remote_ip(), $user->login
    ));
    ThrowUserError('antispam_comment_blocked');
  }
}

#
# domain blocking
#

sub _domain_blocking {
  my ($self, $login) = @_;
  my $address = Email::Address->new(undef, $login);
  my $blocked
    = Bugzilla->dbh->selectrow_array(
    "SELECT 1 FROM antispam_domain_blocklist WHERE domain=?",
    undef, $address->host);
  if ($blocked) {
    Bugzilla->audit(sprintf(
      "blocked <%s> from creating %s, blacklisted domain",
      remote_ip(), $login
    ));
    ThrowUserError('account_creation_restricted');
  }
}

#
# ip blocking
#

sub _ip_blocking {
  my ($self, $login) = @_;
  my $ip = remote_ip();
  my $blocked
    = Bugzilla->dbh->selectrow_array(
    "SELECT 1 FROM antispam_ip_blocklist WHERE ip_address=?",
    undef, $ip);
  if ($blocked) {
    Bugzilla->audit(
      sprintf("blocked <%s> from creating %s, blacklisted IP", $ip, $login));
    ThrowUserError('account_creation_restricted');
  }
}

#
# cc/flag/etc count restrictions
#

sub _is_limited_user {
  return Bugzilla->user->creation_age
    < Bugzilla->params->{antispam_multi_user_limit_age};
}

sub bug_before_create {
  my ($self, $args) = @_;
  $self->_cc_limit($args->{params}, 'cc');
}

sub bug_start_of_set_all {
  my ($self, $args) = @_;
  $self->_cc_limit($args->{params}, 'newcc');
}

sub _cc_limit {
  my ($self, $params, $cc_field) = @_;
  return unless _is_limited_user();
  return unless exists $params->{$cc_field};

  my $cc_count = ref($params->{$cc_field}) ? scalar(@{$params->{$cc_field}}) : 1;
  if ($cc_count > Bugzilla->params->{antispam_multi_user_limit_count}) {
    Bugzilla->audit(
      sprintf("blocked <%s> from CC'ing %s users", Bugzilla->user->login, $cc_count));
    delete $params->{$cc_field};
    if (exists $params->{cc} && exists $params->{cc}->{add}) {
      delete $params->{cc}->{add};
    }
  }
}

sub bug_set_flags {
  my ($self, $args) = @_;
  return unless _is_limited_user();

  my $flag_count = @{$args->{new_flags}};
  if ($flag_count > Bugzilla->params->{antispam_multi_user_limit_count}) {
    Bugzilla->audit(sprintf(
      "blocked <%s> from flaging %s users",
      Bugzilla->user->login, $flag_count
    ));

    # empty the arrayref
    $#{$args->{new_flags}} = -1;
  }
}

#
# spam user disabling
#

sub comment_after_add_tag {
  my ($self, $args) = @_;
  my $tag = lc($args->{tag});
  return unless $tag eq 'spam' or $tag eq 'abusive' or $tag eq 'abuse';
  my $comment = $args->{comment};
  my $author  = $comment->author;

  # exclude disabled users
  return if !$author->is_enabled;

  # exclude users by group
  return if $author->in_group(Bugzilla->params->{antispam_spammer_exclude_group});

  # exclude users who are no longer new
  return if !$author->is_new;

  # exclude users who haven't made enough comments
  my $count
    = $tag eq 'spam'
    ? Bugzilla->params->{antispam_spammer_comment_count}
    : Bugzilla->params->{antispam_abusive_comment_count};
  return if $author->comment_count < $count;

  # get user's comments
  my $comments = Bugzilla->dbh->selectall_arrayref("
        SELECT longdescs.comment_id,longdescs_tags.id
          FROM longdescs
          LEFT JOIN longdescs_tags
               ON longdescs_tags.comment_id = longdescs.comment_id
               AND longdescs_tags.tag = ?
         WHERE longdescs.who = ?
         ORDER BY longdescs.bug_when
    ", undef, $tag, $author->id);

  # this comment needs to be counted too
  my $comment_id = $comment->id;
  foreach my $ra (@$comments) {
    if ($ra->[0] == $comment_id) {
      $ra->[1] = 1;
      last;
    }
  }

  # throw away comment id and negate bool to make it a list of not-spam/abuse
  $comments = [map { $_->[1] ? 0 : 1 } @$comments];

  my $reason;

  # check if the first N comments are spam/abuse
  if (!scalar(grep {$_} @$comments[0 .. ($count - 1)])) {
    $reason = "first $count comments are $tag";
  }

  # check if the last N comments are spam/abuse
  elsif (!scalar(grep {$_} @$comments[-$count .. -1])) {
    $reason = "last $count comments are $tag";
  }

  # disable
  if ($reason) {
    $author->set_disabledtext($tag eq 'spam'
      ? Bugzilla->params->{antispam_spammer_disable_text}
      : Bugzilla->params->{antispam_abusive_disable_text});
    $author->set_disable_mail(1);
    $author->update();
    Bugzilla->audit(sprintf("antispam disabled <%s>: %s", $author->login, $reason));
  }
}

#
# hooks
#

sub object_end_of_create_validators {
  my ($self, $args) = @_;
  if ($args->{class} eq 'Bugzilla::Comment') {
    $self->_comment_blocking($args->{params});
  }
}

sub user_verify_login {
  my ($self, $args) = @_;
  if (my $api_key = Bugzilla->params->{honeypot_api_key}) {
    $self->_project_honeypot_blocking($api_key, $args->{login});
  }
  $self->_ip_blocking($args->{login});
  $self->_domain_blocking($args->{login});
}

sub editable_tables {
  my ($self, $args) = @_;
  my $tables = $args->{tables};

  # allow these tables to be edited with the EditTables extension
  $tables->{antispam_domain_blocklist} = {
    id_field => 'id',
    order_by => 'domain',
    blurb =>
      'List of fully qualified domain names to block at account creation time.',
    group => 'can_configure_antispam',
  };
  $tables->{antispam_comment_blocklist} = {
    id_field => 'id',
    order_by => 'word',
    blurb =>
      "List of whole words that will cause comments containing \\b\$word\\b to be blocked.\n"
      . "This only applies to comments on bugs which the user didn't report.\n"
      . "Users in the editbugs group are exempt from comment blocking.",
    group => 'can_configure_antispam',
  };
  $tables->{antispam_ip_blocklist} = {
    id_field => 'id',
    order_by => 'ip_address',
    blurb => 'List of IPv4 addresses which are prevented from creating accounts.',
    group => 'can_configure_antispam',
  };
}

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{AntiSpam} = "Bugzilla::Extension::AntiSpam::Config";
}

#
# installation
#

sub install_before_final_checks {
  if (!Bugzilla::Group->new({name => 'can_configure_antispam'})) {
    Bugzilla::Group->create({
      name        => 'can_configure_antispam',
      description => 'Can configure Anti-Spam measures',
      isbuggroup  => 0,
    });
  }
}

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{'schema'}->{'antispam_domain_blocklist'} = {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      domain  => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
      comment => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
    ],
    INDEXES =>
      [antispam_domain_blocklist_idx => {FIELDS => ['domain'], TYPE => 'UNIQUE',},],
  };
  $args->{'schema'}->{'antispam_comment_blocklist'} = {
    FIELDS => [
      id   => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      word => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
    ],
    INDEXES =>
      [antispam_comment_blocklist_idx => {FIELDS => ['word'], TYPE => 'UNIQUE',},],
  };
  $args->{'schema'}->{'antispam_ip_blocklist'} = {
    FIELDS => [
      id         => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      ip_address => {TYPE => 'VARCHAR(15)',  NOTNULL => 1,},
      comment    => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
    ],
    INDEXES =>
      [antispam_ip_blocklist_idx => {FIELDS => ['ip_address'], TYPE => 'UNIQUE',},],
  };
}

__PACKAGE__->NAME;
