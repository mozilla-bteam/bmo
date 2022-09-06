#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use autodie;

use lib qw( . qa/t/lib local/lib/perl5 );

use Mojo::Base -strict;
use QA::Util;
use Test::More;

# Bad passwords
use constant BAD_PASSWORDS => (
  {desc => 'too short', error => 'Password Too Short', password => 'a'},
  {
    desc     => 'all lowercase',
    error    => 'Password Fails Requirements',
    password => 'abcdefghijkl'
  },
  {
    desc     => 'all uppercase',
    error    => 'Password Fails Requirements',
    password => 'ABCDEFGHIJKL'
  },
  {
    desc     => 'all numbers',
    error    => 'Password Fails Requirements',
    password => '012345678901'
  },
  {
    desc     => 'too few words',
    error    => 'Password Fails Requirements',
    password => 'abc def ghij'
  },
  {
    desc     => 'not complex enough',
    error    => 'Password Fails Requirements',
    password => 'abcdefghijk1'
  }
);

# Good passwords
use constant GOOD_PASSWORDS => (
  {
    desc     => 'complex password with numbers, lowercase letters, and special characters',
    password => '012!password'
  },
  {
    desc =>
      'complex password with lowercase letters, uppercase letters, and longer than min length',
    password => 'abcdefGHIJKLM'
  },
  {
    desc     => 'complex password: letters, numbers, and longer than min length',
    password => 'password12345'
  },
  {
    desc     => 'phrase password with at least 4 words, each with at least 3 letters',
    password => 'this is a good password with words'
  },
  {
    desc     => 'phrase password containing a complex word',
    password => 'abc def ghijklMNOP01'
  }
);

my @require_env = qw(
  BZ_BASE_URL
  BZ_TEST_NEWBIE
  BZ_TEST_NEWBIE_PASS
  TWD_HOST
  TWD_PORT
);

my @missing_env = grep { !exists $ENV{$_} } @require_env;
bail_out("Missing env: @missing_env") if @missing_env;

my ($sel, $config) = get_selenium();

my $ADMIN_LOGIN  = $config->{admin_user_login};
my $ADMIN_PW_OLD = $config->{admin_user_passwd};

$sel->set_implicit_wait_timeout(600);

$sel->login_ok($ADMIN_LOGIN, $ADMIN_PW_OLD);

# Incorrect old password
$sel->change_password($ADMIN_PW_OLD . 'x', 'password', 'password');
$sel->title_is('Incorrect Old Password');

# Run through each of the bad password tests
foreach my $test (BAD_PASSWORDS) {
  $sel->change_password($ADMIN_PW_OLD, $test->{password}, $test->{password});
  $sel->title_is($test->{error}, $test->{desc});
}

# Run through each of the good password tests
my $last_password;
foreach my $test (GOOD_PASSWORDS) {
  $last_password ||= $ADMIN_PW_OLD;
  $sel->change_password($last_password, $test->{password}, $test->{password});
  $sel->title_is('User Preferences', $test->{desc});
  $last_password = $test->{password};
}

# Set back to original password
$sel->change_password($last_password, $ADMIN_PW_OLD, $ADMIN_PW_OLD);
$sel->title_is("User Preferences");
$sel->logout_ok();

$sel->login_ok($ENV{BZ_TEST_NEWBIE}, $ENV{BZ_TEST_NEWBIE_PASS});

$sel->get_ok("/editusers.cgi");
$sel->title_is("Authorization Required");
$sel->logout_ok();

$sel->login_ok($ADMIN_LOGIN, $ADMIN_PW_OLD);

$sel->toggle_require_password_change($ENV{BZ_TEST_NEWBIE});
$sel->logout_ok();

$sel->login($ENV{BZ_TEST_NEWBIE}, $ENV{BZ_TEST_NEWBIE_PASS});
$sel->title_is('Password change required');
$sel->click_and_type("old_password",  $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_and_type("new_password1", "password");
$sel->click_and_type("new_password2", "password");
$sel->click_ok('//input[@id="submit"]');
$sel->title_is('Password Too Short');

$sel->go_back_ok();
$sel->title_is('Password change required');
$sel->click_and_type("old_password",  $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_and_type("new_password1", "!!" . $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_and_type("new_password2", "!!" . $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_ok('//input[@id="submit"]');
$sel->title_is('Password Changed');
$sel->change_password(
  "!!" . $ENV{BZ_TEST_NEWBIE_PASS},
  $ENV{BZ_TEST_NEWBIE_PASS},
  $ENV{BZ_TEST_NEWBIE_PASS}
);
$sel->title_is("User Preferences");

$sel->get_ok("/userprefs.cgi?tab=account");
$sel->title_is("User Preferences");
$sel->click_link("I forgot my password");
$sel->body_text_contains(
  [
    "A token for changing your password has been emailed to you.",
    "Follow the instructions in that email to change your password."
  ],
);
my $token = $sel->get_token();
ok($token, "got a token from resetting password");
$sel->get_ok("/token.cgi?t=$token&a=cfmpw");
$sel->title_is('Change Password');
$sel->click_and_type("password",      "nopandas1234");
$sel->click_and_type("matchpassword", "nopandas1234");
$sel->click_ok('//input[@id="update"]');
$sel->title_is('Password Fails Requirements');
$sel->go_back_ok();
$sel->title_is('Change Password');
$sel->click_and_type("password",      '??' . $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_and_type("matchpassword", '??' . $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_ok('//input[@id="update"]');
$sel->title_is('Password Changed');
$sel->get_ok("/token.cgi?t=$token&a=cfmpw");
$sel->title_is('Token Does Not Exist');
$sel->get_ok("/login");
$sel->title_is('Log in to Bugzilla');
$sel->login_ok($ENV{BZ_TEST_NEWBIE}, "??" . $ENV{BZ_TEST_NEWBIE_PASS});
$sel->change_password(
  "??" . $ENV{BZ_TEST_NEWBIE_PASS},
  $ENV{BZ_TEST_NEWBIE_PASS},
  $ENV{BZ_TEST_NEWBIE_PASS}
);
$sel->title_is("User Preferences");

$sel->logout_ok();
open my $fh, '>', '/app/data/mailer.testfile';
close $fh;

$sel->get_ok('/createaccount.cgi');
$sel->title_is('Create a new Bugzilla account');
$sel->click_and_type('login', $ENV{BZ_TEST_NEWBIE2});
$sel->find_element('//input[@id="etiquette"]', 'xpath')->click();
$sel->click_ok('//input[@value="Create Account"]');
$sel->title_is(
  "Request for new user account '$ENV{BZ_TEST_NEWBIE2}' submitted");
my ($create_token)
  = $sel->search_mailer_testfile(
  qr{/token\.cgi\?t=([^&]+)&a=request_new_account}xs);
$sel->get_ok("/token.cgi?t=$create_token&a=request_new_account");
$sel->click_and_type('passwd1', $ENV{BZ_TEST_NEWBIE2_PASS});
$sel->click_and_type('passwd2', $ENV{BZ_TEST_NEWBIE2_PASS});
$sel->click_ok('//input[@value="Create"]');

$sel->title_is('Bugzilla Main Page');
$sel->body_text_contains([
  "The user account $ENV{BZ_TEST_NEWBIE2} has been created", "successfully"
]);

done_testing();

