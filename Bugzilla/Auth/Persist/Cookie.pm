# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Auth::Persist::Cookie;

use 5.10.1;
use strict;
use warnings;

use fields qw();

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Token;

use List::Util qw(first);
use List::MoreUtils qw(any);

sub new {
  my ($class) = @_;
  my $self = fields::new($class);
  return $self;
}

sub persist_login {
  my ($self, $user) = @_;
  my $dbh          = Bugzilla->dbh;
  my $cgi          = Bugzilla->cgi;
  my $input_params = Bugzilla->input_params;

  $dbh->bz_start_transaction();

  my $login_cookie
    = Bugzilla::Token::GenerateUniqueToken('logincookies', 'cookie');

  my $ip_addr = remote_ip();

  $dbh->do('INSERT INTO logincookies (cookie, userid, ipaddr, lastused, auth_method)
    VALUES (?, ?, ?, NOW(), ?)', undef, $login_cookie, $user->id, $ip_addr, $user->auth_method);

  # Issuing a new cookie is a good time to clean up the old
  # cookies.
  $dbh->do("DELETE FROM logincookies WHERE lastused < "
      . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-', MAX_LOGINCOOKIE_AGE, 'DAY'));

  $dbh->bz_commit_transaction();

  # Prevent JavaScript from accessing login cookies.
  my %cookieargs = ('-httponly' => 1);

  # Remember cookie only if admin has told so
  # or admin didn't forbid it and user told to remember.
  if (
    Bugzilla->params->{'rememberlogin'} eq 'on'
    || ( Bugzilla->params->{'rememberlogin'} ne 'off'
      && $input_params->{'Bugzilla_remember'}
      && $input_params->{'Bugzilla_remember'} eq 'on')
    )
  {
    # Not a session cookie, so set an infinite expiry
    $cookieargs{'-expires'} = 'Fri, 01-Jan-2038 00:00:00 GMT';
  }
  if (Bugzilla->params->{'ssl_redirect'}) {

    # Make these cookies only be sent to us by the browser during
    # HTTPS sessions, if we're using SSL.
    $cookieargs{'-secure'} = 1;
  }

  $cgi->remove_cookie('github_token');
  $cgi->remove_cookie('Bugzilla_login_request_cookie');
  $cgi->send_cookie(-name => 'Bugzilla_login', -value => $user->id, %cookieargs);
  $cgi->send_cookie(
    -name  => 'Bugzilla_logincookie',
    -value => $login_cookie,
    %cookieargs
  );

  my $securemail_groups
    = Bugzilla->can('securemail_groups')
    ? Bugzilla->securemail_groups
    : ['admin'];

  if (any { $user->in_group($_) } 'mozilla-employee-confidential',
    @$securemail_groups)
  {
    Bugzilla->audit(
      sprintf "successful login of %s from %s using \"%s\", authenticated by %s",
      $user->login, $ip_addr, $cgi->user_agent // '', $user->auth_method);
  }

  return $login_cookie;
}

sub logout {
  my ($self, $param) = @_;

  my $dbh   = Bugzilla->dbh;
  my $cgi   = Bugzilla->cgi;
  my $input = Bugzilla->input_params;
  $param = {} unless $param;
  my $user = $param->{user} || Bugzilla->user;
  my $type = $param->{type} || LOGOUT_ALL;

  if ($type == LOGOUT_ALL) {
    $dbh->do("DELETE FROM logincookies WHERE userid = ?", undef, $user->id);
    return;
  }

  # The LOGOUT_*_CURRENT options require the current login cookie.
  # If a new cookie has been issued during this run, that's the current one.
  # If not, it's the one we've received.
  my @login_cookies;
  my $cookie = first { $_->name eq 'Bugzilla_logincookie' }
  @{$cgi->{'Bugzilla_cookie_list'}};
  if ($cookie) {
    push(@login_cookies, $cookie->value);
  }
  else {
    push(@login_cookies, $cgi->cookie("Bugzilla_logincookie"));
  }

  # If we are a webservice using a token instead of cookie
  # then add that as well to the login cookies to delete
  if (my $login_token = $user->authorizer->login_token) {
    push(@login_cookies, $login_token->{'login_token'});
  }

  # Make sure that @login_cookies is not empty to not break SQL statements.
  push(@login_cookies, '') unless @login_cookies;

  # These queries use both the cookie ID and the user ID as keys. Even
  # though we know the userid must match, we still check it in the SQL
  # as a sanity check, since there is no locking here, and if the user
  # logged out from two machines simultaneously, while someone else
  # logged in and got the same cookie, we could be logging the other
  # user out here. Yes, this is very very very unlikely, but why take
  # chances? - bbaetz
  @login_cookies = map { $dbh->quote($_) } @login_cookies;
  if ($type == LOGOUT_KEEP_CURRENT) {
    $dbh->do(
      "DELETE FROM logincookies WHERE "
        . $dbh->sql_in('cookie', \@login_cookies, 1)
        . " AND userid = ?",
      undef, $user->id
    );
  }
  elsif ($type == LOGOUT_CURRENT) {
    $dbh->do(
      "DELETE FROM logincookies WHERE "
        . $dbh->sql_in('cookie', \@login_cookies)
        . " AND userid = ?",
      undef, $user->id
    );
  }
  else {
    die("Invalid type $type supplied to logout()");
  }

  if ($type != LOGOUT_KEEP_CURRENT) {
    clear_browser_cookies();
  }

}

sub clear_browser_cookies {
  my $cgi = Bugzilla->cgi;
  $cgi->remove_cookie('Bugzilla_login');
  $cgi->remove_cookie('Bugzilla_logincookie');
  $cgi->remove_cookie('sudo');
}

1;
