#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use autodie;

use lib qw( . qa/t/lib local/lib/perl5 );

use Mojo::Base -strict;
use QA::Util;
use Test::More;

BEGIN {
  plan skip_all => "these tests only run in CI"
    unless $ENV{CI} && $ENV{CIRCLE_JOB} eq 'test_bmo';
}

my $ADMIN_LOGIN  = $ENV{BZ_TEST_ADMIN}         // 'admin@mozilla.bugs';
my $ADMIN_PW_OLD = $ENV{BZ_TEST_ADMIN_PASS}    // 'Te6Oovohch';
my $ADMIN_PW_NEW = $ENV{BZ_TEST_ADMIN_NEWPASS} // 'she7Ka8t';

my @require_env = qw(
  BZ_BASE_URL
  BZ_TEST_NEWBIE_USER
  BZ_TEST_NEWBIE_PASS
  TWD_HOST
  TWD_PORT
);

my @missing_env = grep { !exists $ENV{$_} } @require_env;
BAIL_OUT("Missing env: @missing_env") if @missing_env;

my ($sel, $config) = get_selenium();

$sel->set_implicit_wait_timeout(600);

$sel->login_ok($ADMIN_LOGIN, $ADMIN_PW_OLD);

$sel->change_password($ADMIN_PW_OLD . "x", "newpassword2", "newpassword2");
$sel->title_is("Incorrect Old Password");

$sel->change_password($ADMIN_PW_OLD, "password", "password");
$sel->title_is("Password Fails Requirements");

$sel->change_password($ADMIN_PW_OLD, $ADMIN_PW_NEW, $ADMIN_PW_NEW);
$sel->title_is("User Preferences");
$sel->logout_ok();

$sel->login_ok($ADMIN_LOGIN, $ADMIN_PW_NEW);

# we don't protect against password re-use
$sel->change_password($ADMIN_PW_NEW, $ADMIN_PW_OLD, $ADMIN_PW_OLD);
$sel->title_is("User Preferences");
$sel->logout_ok();

$sel->login_ok($ENV{BZ_TEST_NEWBIE_USER}, $ENV{BZ_TEST_NEWBIE_PASS});

$sel->get_ok("/editusers.cgi");
$sel->title_is("Authorization Required");
$sel->logout_ok();

$sel->login_ok($ADMIN_LOGIN, $ADMIN_PW_OLD);

$sel->toggle_require_password_change($ENV{BZ_TEST_NEWBIE_USER});
$sel->logout_ok();

$sel->login($ENV{BZ_TEST_NEWBIE_USER}, $ENV{BZ_TEST_NEWBIE_PASS});
$sel->title_is('Password change required');
$sel->click_and_type("old_password",  $ENV{BZ_TEST_NEWBIE_PASS});
$sel->click_and_type("new_password1", "password");
$sel->click_and_type("new_password2", "password");
$sel->click_ok('//input[@id="submit"]');
$sel->title_is('Password Fails Requirements');

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
$sel->click_and_type("password",      "nopandas");
$sel->click_and_type("matchpassword", "nopandas");
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
$sel->login_ok($ENV{BZ_TEST_NEWBIE_USER}, "??" . $ENV{BZ_TEST_NEWBIE_PASS});
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
$sel->click_and_type('login', $ENV{BZ_TEST_NEWBIE2_USER});
$sel->find_element('//input[@id="etiquette"]', 'xpath')->click();
$sel->click_ok('//input[@value="Create Account"]');
$sel->title_is(
  "Request for new user account '$ENV{BZ_TEST_NEWBIE2_USER}' submitted");
my ($create_token)
  = $sel->search_mailer_testfile(
  qr{/token\.cgi\?t=([^&]+)&a=request_new_account}xs);
$sel->get_ok("/token.cgi?t=$create_token&a=request_new_account");
$sel->click_and_type('passwd1', $ENV{BZ_TEST_NEWBIE2_PASS});
$sel->click_and_type('passwd2', $ENV{BZ_TEST_NEWBIE2_PASS});
$sel->click_ok('//input[@value="Create"]');

$sel->title_is('Bugzilla Main Page');
$sel->body_text_contains([
  "The user account $ENV{BZ_TEST_NEWBIE2_USER} has been created", "successfully"
]);

done_testing();

