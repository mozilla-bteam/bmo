#!/usr/bin/perl
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
    # There's a plugin called Hostage that makes the application require specific Host: headers.
    # we disable that for these tests.
    $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

# this provides a default urlbase.
# Most localconfig options the other Bugzilla::Test::Mock* modules take care for us.
use Bugzilla::Test::MockLocalconfig ( urlbase => 'http://bmo-web.vm' );

# This configures an in-memory sqlite database.
use Bugzilla::Test::MockDB;

# This redirects reads and writes from the config file (data/params)
use Bugzilla::Test::MockParams (
    phabricator_enabled => 1,
    announcehtml        => '<div id="announcement">Mojo::Test is awesome</div>',
);

# Util provides a few functions more making mock data in the DB.
use Bugzilla::Test::Util qw(create_user issue_api_key);

use Test2::V0;
use Test2::Tools::Mock;
use Test::Mojo;

use Bugzilla;

my @calls;

my $Datadog = mock 'DataDog::DogStatsd' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        increment => sub { push @calls, [@_] }
    ]
);
my $Bugzilla = mock 'Bugzilla' => (
    override => [
        datadog => sub { DataDog::Statsd->fake_new }
    ],
);


my $api_user = create_user('api@mozilla.org', '*');
my $api_key  = issue_api_key('api@mozilla.org')->api_key;

# Mojo::Test loads the application and provides methods for
# testing requests without having to run a server.
my $t = Test::Mojo->new('Bugzilla::Quantum');

# Phabricator tells BMO that the Phabricator revision's permissions need to
# be reconciled with the BMO permissions by POSTing a callback URL.
$t->post_ok('/rest/phabbugz/build_target/1234/PHID-HMBT-1234' => { 'X-Bugzilla-API-Key' => $api_key });
$t->status_is(200);

is(['some.metric'], @calls, "Expected one metrics call.");

# Check that calls to other URLs don't increment the counter.
@calls = [];

$t->get_ok('/rest/whoami' => { 'X-Bugzilla-API-Key' => $api_key });
$t->status_is(200);

is([], @calls, "Expected metrics calls to be empty.");


done_testing;
