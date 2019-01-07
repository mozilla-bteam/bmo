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
use Storable qw(freeze);

# this provides a default urlbase.
# Most localconfig options the other Bugzilla::Test::Mock* modules take care for us.
use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo-web.vm');

use Bugzilla::Test::MockParams ( antispam_multi_user_limit_age => 0);

# This configures an in-memory sqlite database.
use Bugzilla::Test::MockDB;

# Util provides a few functions more making mock data in the DB.
use Bugzilla::Test::Util qw(create_user create_bug );

use Test2::V0;
use Test2::Tools::Mock;

use ok 'Bugzilla::Task::BulkEdit';

my $user = create_user('bender@test.bot', '*');
Bugzilla->set_user($user);

my @bug_ids;
foreach (1..100) {
  my $bug = create_bug(
    short_desc  => "a bug",
    comment     => "this is a bug",
    assigned_to => scalar $user->login,
  );
  push @bug_ids, $bug->id;
}

is(0+@bug_ids, 100, "made 100 bugs");

my $task = Bugzilla::Task::BulkEdit->new(
  user => $user,
  ids => \@bug_ids,
  set_all => {
    comment => {
      body => "bunnies",
      is_private => 0,
    },
  }
);
$task->prepare;

try_ok {
  local $Storable::Deparse = 0;
  freeze($task);
} "Can we store the bulk edit task?";

my $results = $task->run;
if (my $edits   = $results->{edits}) {
  is(0 + @$edits, 100);
}

my $comments = Bugzilla::Bug->check($bug_ids[-1])->comments;
is(0 + @$comments, 2);

done_testing;
