#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Regression test for Bug 2035570: Blind SSRF via SES SubscriptionConfirmation.
# The SubscribeURL must be an AWS SNS HTTPS endpoint before any fetch is made.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}         = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE}     = 1;
  $ENV{BUGZILLA_ALLOW_INSECURE_HTTP} = 1;
}

use Bugzilla::Test::MockLocalconfig (
  urlbase      => 'http://bmo.test',
  ses_username => 'ses',
  ses_password => 'ses_password',
);
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams ();

use Test2::V0;
use Test2::Tools::Mock;
use Test::Mojo;
use HTTP::Response ();
use LWP::UserAgent ();
use MIME::Base64 qw(encode_base64);
use JSON::MaybeXS qw(encode_json);

my $t    = Test::Mojo->new('Bugzilla::App');
my $auth = 'Basic ' . encode_base64('ses:ses_password', '');

sub post_subscription {
  my ($url) = @_;
  return $t->post_ok(
    '/ses/index.cgi',
    {
      'X-Amz-SNS-Message-Type' => 'SubscriptionConfirmation',
      'Authorization'          => $auth,
    },
    encode_json({SubscribeURL => $url}),
  );
}

# -----------------------------------------------------------------------
# SSRF: every non-SNS URL must be rejected with 400 before any fetch.
# -----------------------------------------------------------------------
my @ssrf_cases = (
  ['http://169.254.169.254/latest/meta-data/', 'AWS instance metadata (no HTTPS)'],
  ['http://172.18.0.1:8080/',                  'Docker-internal RFC1918 address'],
  ['http://localhost:3306/',                    'localhost port scan'],
  ['http://10.0.0.1/',                          'RFC1918 10.x.x.x'],
  ['https://evil.com/subscribe',               'arbitrary external HTTPS domain'],
  ['https://sns.amazonaws.com.evil.com/',      'SNS domain used as subdomain (spoofing)'],
  ['http://sns.us-east-1.amazonaws.com/',      'valid SNS host but plain HTTP (no TLS)'],
  ['https://notsns.us-east-1.amazonaws.com/', 'amazonaws.com but wrong subdomain prefix'],
);

for my $case (@ssrf_cases) {
  my ($url, $desc) = @$case;
  post_subscription($url)->status_is(400, "Blocked SSRF attempt: $desc");
}

# -----------------------------------------------------------------------
# Valid AWS SNS subscription URLs must be accepted (UA mocked — no network).
# Use a real LWP::UserAgent with a request_send handler so all LWP methods
# are present; only the actual network send is intercepted.
# -----------------------------------------------------------------------
my $mock_ses = mock 'Bugzilla::App::Controller::SES' => (
  override => [
    ua => sub {
      my $ua = LWP::UserAgent->new(timeout => 5);
      $ua->add_handler(
        request_send => sub {
          return HTTP::Response->new(200, 'OK', undef, '');
        }
      );
      return $ua;
    },
  ],
);

my @valid_cases = (
  [
    'https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc123',
    'us-east-1'
  ],
  [
    'https://sns.eu-west-1.amazonaws.com/?Action=ConfirmSubscription&Token=xyz',
    'eu-west-1'
  ],
  [
    'https://sns.ap-southeast-2.amazonaws.com/?Action=ConfirmSubscription&Token=qrs',
    'ap-southeast-2'
  ],
);

for my $case (@valid_cases) {
  my ($url, $region) = @$case;
  post_subscription($url)->status_is(200, "Accepted valid SNS URL for region $region");
}

done_testing;
