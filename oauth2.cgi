#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;

my $c     = $Bugzilla::App::CGI::C;
my $cache = Bugzilla->request_cache;
my $cgi   = Bugzilla->cgi;

# GET requests come from OAuth2 provider,
# with this script acting as the OAuth2 callback.

# Get access token from OAuth2 provider;
my $resp = $c->oauth2->get_token('oauth2');

# Store access token for use by OAuth2 login info getter
$cache->{oauth2_client_userinfo} = $c->oauth2->userinfo($resp->{access_token});

my $user = Bugzilla->login(LOGIN_REQUIRED);

# Go back where we came from
$cgi->redirect($cgi->param('redirect'));
