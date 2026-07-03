#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#####################################################
# Test for REST call to User.create()               #
# POST /rest/user                                    #
#####################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants qw(USER_PASSWORD_MIN_LENGTH);
use QA::Util qw(get_config random_string);

use Test::Mojo;
use Test::More;

use constant NEW_PASSWORD => 'UiX1Shuuchid';
use constant NEW_FULLNAME => 'WebService Created User';

use constant PASSWORD_TOO_SHORT     => 'a';
use constant PASSWORD_TOO_FEW_WORDS => 'bip bop boop';
use constant PASSWORD_NOT_COMPLEX   => 'abcdefghijk1';

# These are the characters that are actually invalid per RFC.
use constant INVALID_EMAIL => '()[]\;:,<>@webservice.test';

sub new_login {
  return 'created_' . random_string(@_) . '@webservice.test';
}

my $config = get_config();
my $url    = Bugzilla->localconfig->urlbase;

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

my @tests = (

  # Permissions checks
  {
    args =>
      {email => new_login(), full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "you are not authorized",
    test  => 'Logged-out user cannot call User.create',
  },
  {
    user => 'unprivileged',
    args =>
      {email => new_login(), full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "you are not authorized",
    test  => 'Unprivileged user cannot call User.create',
  },

  # Login name checks.
  {
    user  => 'admin',
    args  => {full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "argument was not set",
    test  => 'Leaving out email argument fails',
  },
  {
    user  => 'admin',
    args  => {email => '', full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "argument was not set",
    test  => "Passing an empty email argument fails",
  },
  {
    user => 'admin',
    args =>
      {email => INVALID_EMAIL, full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "didn't pass our syntax checking",
    test  => 'Invalid email address fails',
  },
  {
    user => 'admin',
    args =>
      {email => new_login(128), full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    error => "didn't pass our syntax checking",
    test  => 'Too long (> 127 chars) email address fails',
  },
  {
    user => 'admin',
    args => {
      email     => $config->{unprivileged_user_login},
      full_name => NEW_FULLNAME,
      password  => NEW_PASSWORD
    },
    error => "There is already an account",
    test  => 'Trying to use an existing login name fails',
  },
  {
    user => 'admin',
    args =>
      {email => new_login(), full_name => NEW_FULLNAME, password => PASSWORD_TOO_SHORT},
    error =>
      'The password must be at least ' . USER_PASSWORD_MIN_LENGTH . ' characters long.',
    test => 'Password is too short',
  },
  {
    user => 'admin',
    args => {
      email     => new_login(),
      full_name => NEW_FULLNAME,
      password  => PASSWORD_TOO_FEW_WORDS
    },
    error => 'Password must be at least ' . USER_PASSWORD_MIN_LENGTH
      . ' characters long. And the password must also contain either of the following',
    test => 'Password is phrase with too few words',
  },
  {
    user => 'admin',
    args =>
      {email => new_login(), full_name => NEW_FULLNAME, password => PASSWORD_NOT_COMPLEX},
    error => 'Password must be at least ' . USER_PASSWORD_MIN_LENGTH
      . ' characters long. And the password must also contain either of the following',
    test => 'Password not complex enough',
  },
  {
    user => 'admin',
    args =>
      {email => new_login(), full_name => NEW_FULLNAME, password => NEW_PASSWORD},
    test => 'Creating a user with all arguments and correct privileges',
  },
  {
    user => 'admin',
    args => {email => new_login(), password => NEW_PASSWORD},
    test => 'Leaving out fullname works',
  },
);

foreach my $test (@tests) {
  my %headers;
  if (my $user = $test->{user}) {
    $headers{'X-Bugzilla-API-Key'} = $config->{"${user}_user_api_key"};
  }

  if (my $error = $test->{error}) {
    $t->post_ok(
      $url . 'rest/user' => \%headers => json => $test->{args})->status_isnt(200);
    like($t->tx->res->json->{message}, qr/\Q$error\E/, "$test->{test}: $error");
  }
  else {
    $t->post_ok(
      $url . 'rest/user' => \%headers => json => $test->{args})->status_is(201);
    ok($t->tx->res->json->{id}, "$test->{test}: got a non-zero user id");
  }
}

done_testing();
