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
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Mojo::URL;
use Test2::V0;
use Test::Mojo;

use Bugzilla::User;

use Bugzilla::Test::MockLocalconfig (ses_username => 'ses@mozilla.bugs', ses_password => 'password123456789!');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla::Test::Util qw(create_user);

# Create the bounce user
my $bounce_user = create_user('bouncer@mozilla.bugs', 'password123456789!');

my $t = Test::Mojo->new('Bugzilla::App');

my $ses_data = <DATA>;
my $ses_url = Mojo::URL->new('/ses/index.cgi')->userinfo('ses@mozilla.bugs:password123456789!');

# Bounce 1
$t->post_ok($ses_url => { 'X-Amz-SNS-Message-Type' => 'Notification'} => $ses_data)->status_is(200);

$bounce_user = Bugzilla::User->new($bounce_user->id);

ok($bounce_user->bounce_count == 1, 'Bounce count is 1');
ok($bounce_user->email_disabled, 'Email is disabled');
ok($bounce_user->is_enabled, 'Account is still enabled for normal login');

# Bounce 2
$t->post_ok($ses_url => { 'X-Amz-SNS-Message-Type' => 'Notification'} => $ses_data)->status_is(200);

$bounce_user = Bugzilla::User->new($bounce_user->id);

ok($bounce_user->bounce_count == 2, 'Bounce count is 2');
ok($bounce_user->email_disabled, 'Email is disabled');
ok($bounce_user->is_enabled, 'Account is still enabled for normal login');

# Allow user to reset their email
$t->post_ok('/bounced_emails/' . $bounce_user->id => form => { enable_email => 1 });

$bounce_user = Bugzilla::User->new($bounce_user->id);

ok($bounce_user->bounce_count == 2, 'Bounce count is still 2');
ok($bounce_user->email_enabled, 'Email is enabled again');

# Bounce 3 more times causing account to be locked
$t->post_ok($ses_url => { 'X-Amz-SNS-Message-Type' => 'Notification'} => $ses_data)->status_is(200);
$t->post_ok($ses_url => { 'X-Amz-SNS-Message-Type' => 'Notification'} => $ses_data)->status_is(200);
$t->post_ok($ses_url => { 'X-Amz-SNS-Message-Type' => 'Notification'} => $ses_data)->status_is(200);

$bounce_user = Bugzilla::User->new($bounce_user->id);

ok($bounce_user->bounce_count == 5, 'Bounce count = 5');
ok($bounce_user->email_disabled, 'Email disabled');
ok(!$bounce_user->is_enabled, 'Account is disabled for login');

done_testing;

__DATA__
{"Type":"Notification","Message":"{\"eventType\":\"Bounce\",\"bounce\":{\"bounceType\":\"Permanent\",\"bounceSubType\":\"General\",\"bouncedRecipients\":[{\"emailAddress\":\"bouncer@mozilla.bugs\",\"action\":\"failed\",\"status\":\"5.1.1\",\"diagnosticCode\":\"smtp;5505.1.1userunknown\"}],\"timestamp\":\"2017-08-05T00:41:02.669Z\",\"feedbackId\":\"01000157c44f053b-61b59c11-9236-11e6-8f96-7be8aexample-000000\",\"reportingMTA\":\"dsn;mta.example.com\"},\"mail\":{\"timestamp\":\"2017-08-05T00:40:02.012Z\",\"source\":\"BugzillaDaemon<bugzilla@mozilla.bugs>\",\"sourceArn\":\"arn:aws:ses:us-east-1:123456789012:identity/bugzilla@mozilla.bugs\",\"sendingAccountId\":\"123456789012\",\"messageId\":\"EXAMPLE7c191be45-e9aedb9a-02f9-4d12-a87d-dd0099a07f8a-000000\",\"destination\":[\"bouncer@mozilla.bugs\"],\"headersTruncated\":false,\"headers\":[{\"name\":\"From\",\"value\":\"BugzillaDaemon<bugzilla@mozilla.bugs>\"},{\"name\":\"To\",\"value\":\"bouncer@mozilla.bugs\"},{\"name\":\"Subject\",\"value\":\"MessagesentfromAmazonSES\"},{\"name\":\"MIME-Version\",\"value\":\"1.0\"},{\"name\":\"Content-Type\",\"value\":\"multipart/alternative;boundary=\"}],\"commonHeaders\":{\"from\":[\"BugzillaDaemon<bugzilla@mozilla.bugs>\"],\"to\":[\"bouncer@mozilla.bugs\"],\"messageId\":\"EXAMPLE7c191be45-e9aedb9a-02f9-4d12-a87d-dd0099a07f8a-000000\",\"subject\":\"MessagesentfromAmazonSES\"},\"tags\":{\"ses:configuration-set\":[\"ConfigSet\"],\"ses:source-ip\":[\"192.0.2.0\"],\"ses:from-domain\":[\"example.com\"],\"ses:caller-identity\":[\"ses_user\"]}}}"}
