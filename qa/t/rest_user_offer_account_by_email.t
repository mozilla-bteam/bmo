#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#############################################################
# Test for REST call to User.offer_account_by_email()       #
# POST /rest/user/offer_account_by_email                    #
#############################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use QA::Util qw(get_config random_string);

use Test::Mojo;
use Test::More;

# These are the characters that are actually invalid per RFC.
use constant INVALID_EMAIL => '()[]\;:,<>@webservice.test';

my $config = get_config();
my $url    = Bugzilla->localconfig->urlbase;

sub new_login {
  return 'requested_' . random_string() . '@webservice.test';
}

my $t = Test::Mojo->new();

# Allow 1 redirect max
$t->ua->max_redirects(1);

my $resource = $url . 'rest/user/offer_account_by_email';

# This method is login exempt, so no API key is required.

# Leaving out the email argument fails.
$t->post_ok($resource => json => {})->status_is(400)
  ->json_is('/error' => Mojo::JSON->true)->json_is('/code' => 50)
  ->json_like('/message' => qr/argument was not set/);

# Passing an empty email argument fails.
$t->post_ok($resource => json => {email => ''})->status_is(400)
  ->json_is('/error' => Mojo::JSON->true)->json_is('/code' => 50)
  ->json_like('/message' => qr/argument was not set/);

# An email address that is invalid per RFC fails our syntax checking.
$t->post_ok($resource => json => {email => INVALID_EMAIL})->status_is(400)
  ->json_is('/error' => Mojo::JSON->true)->json_is('/code' => 501)
  ->json_like('/message' => qr/didn't pass our syntax checking/);

# Trying to use an existing login name fails.
$t->post_ok(
  $resource => json => {email => $config->{unprivileged_user_login}})
  ->status_is(400)->json_is('/error' => Mojo::JSON->true)
  ->json_is('/code' => 500)
  ->json_like('/message' => qr/There is already an account/);

# A valid, non-existing email address succeeds and returns nothing.
# (Unlike JSON-RPC, the REST API only exposes this method over POST: the
# route is defined for POST only, so there is no "must use POST" case to
# test here.)
$t->post_ok($resource => json => {email => new_login()})->status_is(200);

done_testing();
