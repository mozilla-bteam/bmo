#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib qa/t/lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Mojo::URL;
use Mojo::UserAgent;
use QA::Util;
use Test::More;

my $ADMIN_LOGIN  = $ENV{BZ_TEST_ADMIN}      // 'admin@mozilla.bugs';
my $ADMIN_PW_OLD = $ENV{BZ_TEST_ADMIN_PASS} // 'Te6Oovohch';
my $SES_USERNAME = $ENV{BMO_ses_username}   // 'ses@mozilla.bugs';
my $SES_PASSWORD = $ENV{BMO_ses_password}   // 'password123456789!';

my @require_env = qw(
  BZ_BASE_URL
  BZ_TEST_BOUNCE_USER
  BZ_TEST_BOUNCE_PASS
  TWD_HOST
  TWD_PORT
);

my @missing_env = grep { !exists $ENV{$_} } @require_env;
BAIL_OUT("Missing env: @missing_env") if @missing_env;

my ($sel, $config) = get_selenium();

my $ua = Mojo::UserAgent->new;
$ua->on(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Amz-SNS-Message-Type' => 'Notification');
  }
);

my $ses_data = <DATA>;
my $ses_url  = Mojo::URL->new($ENV{BZ_BASE_URL} . 'ses/index.cgi')
  ->userinfo("$SES_USERNAME:$SES_PASSWORD");

# First bounce
my $result = $ua->post($ses_url => $ses_data)->result;
ok($result->is_success, 'Posting first bounce was successful');

# Allow user to reset their email
$sel->set_implicit_wait_timeout(600);
$sel->login_ok($ENV{BZ_TEST_BOUNCE_USER}, $ENV{BZ_TEST_BOUNCE_PASS});
$sel->body_text_contains('Change notification emails have been disabled',
  'Email disabled warning is displayed');
$sel->click_element_ok('//a[@id="bounced_emails_link"]');
sleep(2);
$sel->title_is('Bounced Emails');
$sel->click_element_ok('//input[@id="enable_email"]');
$sel->submit('//input[@value="Submit"]');
sleep(2);
$sel->title_is('Bugzilla Main Page');
$sel->body_text_lacks(
  'Change notification emails have been disabled',
  'Email disabled warning is no longer displayed'
);
$sel->logout_ok();

# Bounce 4 more times causing account to be locked
$result = $ua->post($ses_url => $ses_data)->result;
ok($result->is_success, 'Posting third bounce was successful');
$result = $ua->post($ses_url => $ses_data)->result;
ok($result->is_success, 'Posting fourth bounce was successful');
$result = $ua->post($ses_url => $ses_data)->result;
ok($result->is_success, 'Posting fifth bounce was successful');
$result = $ua->post($ses_url => $ses_data)->result;
ok($result->is_success, 'Posting fifth bounce was successful');

# User should not be able to login again
$sel->login($ENV{BZ_TEST_BOUNCE_USER}, $ENV{BZ_TEST_BOUNCE_PASS});
$sel->title_is('Account Disabled');
$sel->body_text_contains(
  'Your Bugzilla account has been disabled due to issues delivering emails to your address.',
  'Account disabled message is displayed'
);

done_testing;

__DATA__
{"Type":"Notification","Message":"{\"eventType\":\"Bounce\",\"bounce\":{\"bounceType\":\"Permanent\",\"bounceSubType\":\"General\",\"bouncedRecipients\":[{\"emailAddress\":\"bouncer@mozilla.example\",\"action\":\"failed\",\"status\":\"5.1.1\",\"diagnosticCode\":\"smtp;5505.1.1userunknown\"}],\"timestamp\":\"2017-08-05T00:41:02.669Z\",\"feedbackId\":\"01000157c44f053b-61b59c11-9236-11e6-8f96-7be8aexample-000000\",\"reportingMTA\":\"dsn;mta.example.com\"},\"mail\":{\"timestamp\":\"2017-08-05T00:40:02.012Z\",\"source\":\"BugzillaDaemon<bugzilla@mozilla.bugs>\",\"sourceArn\":\"arn:aws:ses:us-east-1:123456789012:identity/bugzilla@mozilla.bugs\",\"sendingAccountId\":\"123456789012\",\"messageId\":\"EXAMPLE7c191be45-e9aedb9a-02f9-4d12-a87d-dd0099a07f8a-000000\",\"destination\":[\"bouncer@mozilla.example\"],\"headersTruncated\":false,\"headers\":[{\"name\":\"From\",\"value\":\"BugzillaDaemon<bugzilla@mozilla.bugs>\"},{\"name\":\"To\",\"value\":\"bouncer@mozilla.example\"},{\"name\":\"Subject\",\"value\":\"MessagesentfromAmazonSES\"},{\"name\":\"MIME-Version\",\"value\":\"1.0\"},{\"name\":\"Content-Type\",\"value\":\"multipart/alternative;boundary=\"}],\"commonHeaders\":{\"from\":[\"BugzillaDaemon<bugzilla@mozilla.bugs>\"],\"to\":[\"bouncer@mozilla.example\"],\"messageId\":\"EXAMPLE7c191be45-e9aedb9a-02f9-4d12-a87d-dd0099a07f8a-000000\",\"subject\":\"MessagesentfromAmazonSES\"},\"tags\":{\"ses:configuration-set\":[\"ConfigSet\"],\"ses:source-ip\":[\"192.0.2.0\"],\"ses:from-domain\":[\"example.com\"],\"ses:caller-identity\":[\"ses_user\"]}}}"}
