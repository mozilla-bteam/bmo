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
use Bugzilla;

BEGIN { Bugzilla->extensions }

use Test::More;
use Test2::Tools::Mock;

use ok 'Bugzilla::Extension::PhabBugz::Revision';
use ok 'Bugzilla::Extension::PhabBugz::User';
use ok 'Bugzilla::Extension::PhabBugz::Project';
use ok 'Bugzilla::Extension::PhabBugz::Util', qw(set_reviewer_rotation);

# ===========================================================================
# Package-level state used by mocks. Each test uses 'local' to scope changes.
# ===========================================================================

# Simulates the phab_reviewer_rotation DB table: project_phid => user_phid
our %rotation_db;

# Capture which reviewer was added/removed by set_reviewer_rotation
our @added_reviewers;
our @removed_reviewers;
our @added_comments;

# The revision object that Revision->new_from_query will return
our $current_revision;

# ===========================================================================
# Mock classes
# ===========================================================================

# PhabBugz User: id, phid, name, bugzilla_user are all Moo 'ro' or 'lazy'
# attributes. fake_new blesses the hashref directly, so the accessors find
# the values in the hash without calling any lazy builder.
my $PhabUser = mock 'Bugzilla::Extension::PhabBugz::User' => (
  add_constructor => ['fake_new' => 'hash'],
);

my $PhabProject = mock 'Bugzilla::Extension::PhabBugz::Project' => (
  add_constructor => ['fake_new' => 'hash'],
);

# For the Revision mock:
# - new_from_query returns $current_revision (set per-test with local)
# - add_reviewer / remove_reviewer capture their argument for assertions
# - Other mutating calls are no-ops
my $PhabRevision = mock 'Bugzilla::Extension::PhabBugz::Revision' => (
  add_constructor => ['fake_new' => 'hash'],
  override        => [
    new_from_query  => sub { $current_revision },
    add_reviewer    => sub { push @added_reviewers,   $_[1] },
    remove_reviewer => sub { push @removed_reviewers, $_[1] },
    add_subscriber  => sub { 1 },
    add_comment     => sub { push @added_comments,    $_[1] },
    update          => sub { 1 },
  ],
);

# Bugzilla::User: override can_see_bug and settings to use hash values so
# each test member can declare its own visibility/availability.
my $BugzillaUser = mock 'Bugzilla::User' => (
  add_constructor => ['fake_new' => 'hash'],
  override        => [
    can_see_bug => sub { $_[0]->{can_see_bug}   // 1 },
    settings    => sub {
      +{block_reviews => {value => $_[0]->{block_reviews} // 'off'}}
    },
  ],
);

# Bugzilla::Bug: only needs an id accessor
my $BugzillaBug = mock 'Bugzilla::Bug' => (
  add_constructor => ['fake_new' => 'hash'],
);

# Override find_last_reviewer_phid and update_last_reviewer_phid to use
# %rotation_db instead of the real database. These are non-exported package
# subs called internally by set_reviewer_rotation, so overriding the symbol
# in the Util namespace is sufficient.
# NOTE: These are installed at file scope — individual tests use
# 'local %rotation_db' to control what the DB "contains" per scenario.
{
  no warnings 'redefine';
  *Bugzilla::Extension::PhabBugz::Util::find_last_reviewer_phid = sub {
    my ($project) = @_;
    return $rotation_db{$project->phid};
  };
  *Bugzilla::Extension::PhabBugz::Util::update_last_reviewer_phid = sub {
    my ($project, $reviewer) = @_;
    $rotation_db{$project->phid} = $reviewer->phid;
  };
}

# ===========================================================================
# Helpers
# ===========================================================================

sub make_bz_user {
  my (%args) = @_;
  return Bugzilla::User->fake_new(
    can_see_bug   => $args{can_see_bug}   // 1,
    block_reviews => $args{block_reviews} // 'off',
  );
}

sub make_member {
  my (%args) = @_;
  return Bugzilla::Extension::PhabBugz::User->fake_new(
    id            => $args{id},
    phid          => $args{phid},
    name          => $args{name},
    bugzilla_user => make_bz_user(%args),
  );
}

sub make_project {
  my (%args) = @_;
  return Bugzilla::Extension::PhabBugz::Project->fake_new(
    phid    => $args{phid},
    name    => $args{name},
    members => $args{members} // [],
  );
}

sub make_revision {
  my (%args) = @_;
  return Bugzilla::Extension::PhabBugz::Revision->fake_new(
    id          => $args{id}   // 1,
    phid        => $args{phid} // 'PHID-DREV-test001',
    author      => $args{author},
    reviews     => $args{reviews} // [],
    stack_graph => {phids => []},
    comments    => [],
    bug         => Bugzilla::Bug->fake_new(id => $args{bug_id} // 42),
  );
}

# Builds the reviewer entry that appears in $revision->reviews for a
# rotation group project.
sub rotation_review {
  my ($project) = @_;
  return {
    is_project  => 1,
    user        => $project,
    status      => 'added',
    is_blocking => 0,
  };
}

sub reset_state {
  @added_reviewers   = ();
  @removed_reviewers = ();
  @added_comments    = ();
}

# ===========================================================================
# Part 1: rotate_reviewer_list — pure unit tests, no DB or API involved
# ===========================================================================

note '--- Part 1: rotate_reviewer_list ---';

{
  my $a = Bugzilla::Extension::PhabBugz::User->fake_new(
    id => 1, phid => 'PHID-USER-A', name => 'Alice');
  my $b = Bugzilla::Extension::PhabBugz::User->fake_new(
    id => 2, phid => 'PHID-USER-B', name => 'Bob');
  my $c = Bugzilla::Extension::PhabBugz::User->fake_new(
    id => 3, phid => 'PHID-USER-C', name => 'Carol');

  my @members = ($a, $b, $c);
  my @result;

  # No last reviewer: list is unchanged
  @result = Bugzilla::Extension::PhabBugz::Util::rotate_reviewer_list(
    \@members, undef);
  is_deeply([map { $_->name } @result], ['Alice', 'Bob', 'Carol'],
    'no last reviewer: list unchanged');

  # Bob (middle) was last: list rotates to [Carol, Alice, Bob]
  @result = Bugzilla::Extension::PhabBugz::Util::rotate_reviewer_list(
    \@members, 'PHID-USER-B');
  is_deeply([map { $_->name } @result], ['Carol', 'Alice', 'Bob'],
    'last=Bob: rotates to [Carol, Alice, Bob]');

  # Alice (first element) was last: rotates to [Bob, Carol, Alice]
  @result = Bugzilla::Extension::PhabBugz::Util::rotate_reviewer_list(
    \@members, 'PHID-USER-A');
  is_deeply([map { $_->name } @result], ['Bob', 'Carol', 'Alice'],
    'last=Alice (first): rotates to [Bob, Carol, Alice]');

  # Carol (last element) was last: wraps to [Alice, Bob, Carol]
  # ($index+1 .. $#members) is an empty slice; (0 .. $index) is the full list
  @result = Bugzilla::Extension::PhabBugz::Util::rotate_reviewer_list(
    \@members, 'PHID-USER-C');
  is_deeply([map { $_->name } @result], ['Alice', 'Bob', 'Carol'],
    'last=Carol (last element): wraps around to [Alice, Bob, Carol]');

  # Last reviewer has left the group: list is returned unchanged
  @result = Bugzilla::Extension::PhabBugz::Util::rotate_reviewer_list(
    \@members, 'PHID-USER-GONE');
  is_deeply([map { $_->name } @result], ['Alice', 'Bob', 'Carol'],
    'last reviewer left group: list unchanged');
}

# ===========================================================================
# Part 2: set_reviewer_rotation scenarios
# ===========================================================================

note '--- Part 2: set_reviewer_rotation ---';

# Shared members: group [Alice(1), Bob(2), Carol(3)], author = Alice.
# Sorted by id they appear in order A, B, C.
my $alice = make_member(id => 1, phid => 'PHID-USER-A', name => 'Alice');
my $bob   = make_member(id => 2, phid => 'PHID-USER-B', name => 'Bob');
my $carol = make_member(id => 3, phid => 'PHID-USER-C', name => 'Carol');

my $project = make_project(
  phid    => 'PHID-PROJ-rotation',
  name    => 'webdriver-reviewers-rotation',
  members => [$alice, $bob, $carol],
);

# --- No rotation project → returns early, no reviewer assigned ---
do {
  reset_state();
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [],    # no rotation project on this revision
  );
  set_reviewer_rotation($current_revision);
  is(scalar @added_reviewers, 0,
    'no rotation project: no reviewer assigned');
};

# --- First revision (no DB history) → picks first eligible non-author ---
# Sorted order: [Alice, Bob, Carol]. Alice is author, so Bob is picked.
do {
  reset_state();
  local %rotation_db = ();
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [rotation_review($project)],
  );
  set_reviewer_rotation($current_revision);
  is($added_reviewers[0], 'PHID-USER-B',
    'no history: picks first eligible non-author (Bob)');
  is($rotation_db{'PHID-PROJ-rotation'}, 'PHID-USER-B',
    'DB stores Bob as last reviewer');
};

# --- Normal rotation: Bob was last → Carol is picked ---
# Last=Bob, rotated list: [Carol, Alice, Bob]. Carol is eligible → picked.
do {
  reset_state();
  local %rotation_db = ('PHID-PROJ-rotation' => 'PHID-USER-B');
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [rotation_review($project)],
  );
  set_reviewer_rotation($current_revision);
  is($added_reviewers[0], 'PHID-USER-C',
    'Bob was last: rotated list [Carol, Alice, Bob], Carol picked');
  is($rotation_db{'PHID-PROJ-rotation'}, 'PHID-USER-C',
    'DB stores Carol as last reviewer');
};

# --- Key bug fix: last reviewer picked when all others unavailable ---
# Bob was last reviewer. Carol has block_reviews=on. Alice is the author.
# Rotated list: [Carol, Alice, Bob].
# - Carol: block_reviews → skip
# - Alice: is author → skip
# - Bob: last reviewer but still eligible → PICKED (not skipped)
# Before the fix, Bob would have been explicitly skipped, causing failure.
do {
  reset_state();
  my $carol_away = make_member(
    id            => 3,
    phid          => 'PHID-USER-C',
    name          => 'Carol',
    block_reviews => 'on',
  );
  my $project_carol_away = make_project(
    phid    => 'PHID-PROJ-rotation',
    name    => 'webdriver-reviewers-rotation',
    members => [$alice, $bob, $carol_away],
  );
  local %rotation_db = ('PHID-PROJ-rotation' => 'PHID-USER-B');
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [rotation_review($project_carol_away)],
  );
  set_reviewer_rotation($current_revision);
  is($added_reviewers[0], 'PHID-USER-B',
    'Carol away + Alice is author: falls back to last reviewer Bob (bug fix)');
};

# --- Rotation group removed when member is already an individual reviewer ---
# If Bob is already explicitly added as a reviewer (not via a group), the
# rotation group is removed from reviewers and added to subscribers.
do {
  reset_state();
  my $bob_individual_review = {
    is_project  => 0,
    user        => $bob,
    status      => 'added',
    is_blocking => 0,
  };
  local %rotation_db = ('PHID-PROJ-rotation' => 'PHID-USER-B');
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [rotation_review($project), $bob_individual_review],
  );
  set_reviewer_rotation($current_revision);
  is(scalar @added_reviewers, 0,
    'Bob already a reviewer: no new reviewer added by rotation');
  ok((grep { $_ eq 'PHID-PROJ-rotation' } @removed_reviewers),
    'rotation group removed from reviewer list');
};

# --- All members unavailable → "reviewer not found" comment added ---
# Alice is author, Bob and Carol both have block_reviews=on.
# No eligible reviewer exists, so a REVIEWER ROTATION: comment is added.
do {
  reset_state();
  my $bob_away   = make_member(id => 2, phid => 'PHID-USER-B', name => 'Bob',
    block_reviews => 'on');
  my $carol_away = make_member(id => 3, phid => 'PHID-USER-C', name => 'Carol',
    block_reviews => 'on');
  my $project_all_away = make_project(
    phid    => 'PHID-PROJ-rotation',
    name    => 'webdriver-reviewers-rotation',
    members => [$alice, $bob_away, $carol_away],
  );
  local %rotation_db = ();
  local $current_revision = make_revision(
    author  => $alice,
    reviews => [rotation_review($project_all_away)],
  );
  set_reviewer_rotation($current_revision);
  is(scalar @added_reviewers, 0,
    'all members unavailable: no reviewer assigned');
  ok(
    (grep { /REVIEWER ROTATION:.*webdriver-reviewers-rotation/ } @added_comments),
    'all members unavailable: reviewer-not-found comment added'
  );
};

done_testing;
