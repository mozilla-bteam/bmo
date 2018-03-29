#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;
use autodie;

use LWP::UserAgent;
use Test::More 1.302;
use HTTP::Request;
# BEGIN { plan skip_all => "these tests only run in CI" unless $ENV{CI} && $ENV{CIRCLE_JOB} eq 'test_bmo' };

my $ua  = LWP::UserAgent->new;
my $req = HTTP::Request->new(POST => "$ENV{BZ_BASE_URL}/ses/index.cgi");

$req->header( Authorization            => 'Basic c2VzOnNlY3JldA==' );
$req->header( 'Content-Type'           => 'text/plain; charset=UTF-8' );
$req->header( 'x-amz-sns-message-id'   => 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXX' );
$req->header( 'x-amz-sns-message-type' => 'SubscriptionConfirmation' );
$req->header( 'x-amz-sns-topic-arn'    => 'aws:sns:us-west-2:XXXXXXXXXXXX:bugzilla-dev-ses-bounce-handler' );
$req->content(
    q[
        {
        "Type" : "SubscriptionConfirmation",
        "MessageId" : "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXX",
        "Token" : "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXx",
        "TopicArn" : "arn:aws:sns:us-west-2:XXXXXXXXXXXX:bugzilla-dev-ses-bounce-handler",
        "Message" : "You have chosen to subscribe to the topic arn:aws:sns:us-west-2:XXXXXXXXXXXX:bugzilla-dev-ses-bounce-handler.\nTo confirm the subscriptionDataBuilder, visit the SubscribeURL included in this message.",
        "SubscribeURL" : "<FAKE-TEST>",
        "Timestamp" : "2018-03-07T21:10:30.733Z",
        "SignatureVersion" : "1",
        "Signature" : "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXxXXXXXXXXXXXXXXXXXx==",
        "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-XXXXXXXXXXXXXXXXXXXXXXXXXXx.pem"
        }
]);

my $resp = $ua->request($req);

is($resp->code, 200, "subscribe works");


done_testing;

