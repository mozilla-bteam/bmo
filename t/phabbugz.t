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
use Bugzilla;

BEGIN { Bugzilla->extensions };

use Test::More;
use Test2::Tools::Mock;
use Data::Dumper;
use JSON::MaybeXS;
use Carp;

use ok 'Bugzilla::Extension::PhabBugz::Feed';
can_ok('Bugzilla::Extension::PhabBugz::Feed', 'group_query');

our $check_post;
our @group_members;
our @project_members;


my $User = mock 'Bugzilla::Extension::PhabBugz::User' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'match' => sub { [ mock() ] },
    ],
);

my $Feed = mock 'Bugzilla::Extension::PhabBugz::Feed' => (
    override => [
        get_group_members => sub {
            return [ map { Bugzilla::Extension::PhabBugz::User->fake_new(%$_) } @group_members ];
        }
    ]
);

my $Project = mock 'Bugzilla::Extension::PhabBugz::Project' => (
    override_constructor => [
        new_from_query => 'ref_copy',
    ],
    override => [
        'members' => sub {
            return [ map { Bugzilla::Extension::PhabBugz::User->fake_new(%$_) } @project_members ];
        }
    ]
);

my $UserAgent = mock 'LWP::UserAgent' => (
    override => [
        'post' => sub {
            my ($self, $url, $params) = @_;
            $check_post->(decode_json($params->{params}), $url);
            return mock({is_error => 0, content => '{}'});
        },
    ],
);

local Bugzilla->params->{phabricator_enabled} = 1;
local Bugzilla->params->{phabricator_api_key} = 'FAKE-API-KEY';
local Bugzilla->params->{phabricator_base_uri} = 'http://fake.fabricator.tld';

my $Bugzilla = mock 'Bugzilla' => (
    override => [
        'dbh' => sub { mock() },
    ],
);

my $BugzillaGroup = mock 'Bugzilla::Group' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'match' => sub { [ Bugzilla::Group->fake_new(id => 1, name => 'firefox-security' ) ] },
    ],
);

my $BugzillaUser = mock 'Bugzilla::User' => (
    add_constructor => [
        'fake_new' => 'hash',
    ],
    override => [
        'new' => sub {
            my ($class, $hash) = @_;
            if ($hash->{name} eq 'phab-bot@bmo.tld') {
                return $class->fake_new( id => 8_675_309, login_name => 'phab-bot@bmo.tld', realname => 'Fake PhabBot' );
            }
            else {
            }
        },
        'match' => sub { [ mock() ] },
    ],
);


my $feed = Bugzilla::Extension::PhabBugz::Feed->new;

# Same members in both
do {
    local $check_post = sub {
        my $data = shift;
        is_deeply($data->{transactions}, [], 'no-op');
    };
    local @group_members = (
        { phid => 'foo' },
    );
    local @project_members = (
        { phid => 'foo' },
    );
    $feed->group_query;
};

# Project has members not in group
do {
    local $check_post = sub {
        my $data = shift;
        my $expected = [
            {
                type => 'members.remove',
                value => ['foo'],
            }
        ];
        is_deeply($data->{transactions}, $expected, 'remove foo');
    };
    local @group_members = ();
    local @project_members = (
        { phid => 'foo' },
    );
    $feed->group_query;
};

# Group has members not in project
do {
    local $check_post = sub {
        my $data = shift;
        my $expected = [
            {
                type => 'members.add',
                value => ['foo'],
            }
        ];
        is_deeply($data->{transactions}, $expected, 'add foo');
    };
    local @group_members = (
        { phid => 'foo' },
    );
    local @project_members = (
    );
    $feed->group_query;
};

done_testing;
