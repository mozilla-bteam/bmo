# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozillaIAM;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Token qw(issue_hash_token);
use Bugzilla::User;
use Bugzilla::Util qw(trim);

use Bugzilla::Extension::MozillaIAM::Util
  qw(add_staff_member get_access_token get_profile_by_email remove_staff_member);

use Try::Tiny;

our $VERSION = '1';

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{MozillaIAM} = "Bugzilla::Extension::MozillaIAM::Config";
}

sub oauth2_client_pre_login {
  my ($self, $args) = @_;

  return if !Bugzilla->params->{mozilla_iam_enabled};

  my $userinfo     = $args->{userinfo};
  my $iam_username = $userinfo->{email};

  # First check to see if we are already linked with this account
  my $bmo_email = Bugzilla->dbh->selectrow_array(
    'SELECT profiles.login_name
       FROM profiles JOIN profiles_iam ON profiles.userid = profiles_iam.user_id
      WHERE profiles_iam.iam_username = ?', undef, $iam_username
  );

  # If not, query the IAM system to see if they have a BMO address set
  if (!$bmo_email) {
    my $profile = get_profile_by_email($iam_username);
    if ($profile && $profile->{bmo_email}) {
      $bmo_email = $profile->{bmo_email};

      # Save profile data for post login
      $userinfo->{iam_profile_data} = $profile;
    }
  }

  if ($bmo_email && $bmo_email ne $iam_username) {
    $userinfo->{email}        = $bmo_email;
    $userinfo->{iam_username} = $iam_username;
  }
}

sub oauth2_client_post_login {
  my ($self, $args) = @_;

  return if !Bugzilla->params->{mozilla_iam_enabled};

  my $userinfo     = $args->{userinfo};
  my $iam_username = $userinfo->{iam_username} || $userinfo->{email};

  my $profile = $userinfo->{iam_profile_data}
    ||= get_profile_by_email($iam_username);

  if ($profile->{is_staff}) {
    add_staff_member({
      bmo_email    => $profile->{bmo_email},
      iam_username => $profile->{iam_username},
      real_name    => $profile->{first_name} . ' ' . $profile->{last_name},
      is_staff     => $profile->{is_staff},
    });
  }
}


sub oauth2_client_handle_redirect {
  my ($self, $args) = @_;
  my $cgi      = Bugzilla->cgi;
  my $userinfo = $args->{userinfo};

  return if !Bugzilla->params->{mozilla_iam_enabled};

  # Return if this request already came from the Mozilla IAM provider
  # or the user is not logging in through the CGI login form.
  return
    if $userinfo
    || !($cgi->param('Bugzilla_login') && $cgi->param('GoAheadAndLogIn'));

  my $login = $cgi->param('Bugzilla_login');
  my $user  = Bugzilla::User->new({name => $login});

  my $must_redirect = 0;

  # If the user has an IAM account associated then automatically redirect to
  # Mozilla IAM provider.
  if ($user && $user->iam_username) {
    $must_redirect = 1;
  }

  # If the users login matches a mandatory domain, then also redirect
  my @mandatory_domains = split /\n/,
    Bugzilla->params->{mozilla_iam_mandatory_domains};
  foreach my $domain (@mandatory_domains) {
    $domain = trim($domain);
    if ($login =~ /@\Q$domain\E$/) {
      $must_redirect = 1;
      last;
    }
  }

  if ($must_redirect) {
    my $script_name = $cgi->script_name;
    $script_name =~ s{^/}{};
    my $query = $cgi->canonicalize_query(
      'Bugzilla_login',  'Bugzilla_password',
      'GoAheadAndLogIn', 'Bugzilla_login_token'
    );
    my $target
      = Bugzilla->localconfig->basepath . $script_name . ($query ? "?$query" : '');

    my $c             = Bugzilla->request_cache->{mojo_controller};
    my $redirect_uri  = $c->oauth2->redirect_uri($target);
    my $authorize_url = $c->oauth2->auth_url('oauth2',
      {state => issue_hash_token(['oauth2']), redirect_uri => $redirect_uri});

    $cgi->redirect($authorize_url);
  }

  return;
}

sub object_end_of_update {
  my ($self, $args) = @_;
  my ($object, $old_object, $changes) = @$args{qw(object old_object changes)};

  return
    if !Bugzilla->params->{mozilla_iam_enabled}
    || !$object->isa('Bugzilla::User');

  # Remove mapping of profile_iam to profiles if a user has changed their email
  if ($old_object->login ne $object->login && $old_object->iam_username) {
    remove_staff_member({iam_username => $old_object->iam_username});
  }
}

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{'schema'}->{'mozilla_iam_updates'} = {
    FIELDS => [
      id       => {TYPE => 'INTSERIAL',    NOTNULL => 1, PRIMARYKEY => 1},
      type     => {TYPE => 'VARCHAR(255)', NOTNULL => 1},
      value    => {TYPE => 'MEDIUMTEXT',   NOTNULL => 1},
      mod_time => {TYPE => 'DATETIME',     NOTNULL => 1}
    ],
  };
}

__PACKAGE__->NAME;
