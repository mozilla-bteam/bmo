#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Test that cloning a bug across products keeps it secure to the best of
# BMO's ability: when any of the bug's groups would be dropped in the target
# product, the target's default security group is pre-checked. This must work
# even when the bug is only in a non-default security group such as
# dom-core-security, and must NOT add the default when every group carries
# over (Bug 2028240, Bug 2049554).

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
use Test::More;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Bug;
use Bugzilla::Product;
use Bugzilla::Group;
BEGIN { Bugzilla->extensions }

Bugzilla->usage_mode(USAGE_MODE_TEST);
Bugzilla->error_mode(ERROR_MODE_DIE);

# Verify the default_security_group method exists (BMO extension)
my $test_product = (Bugzilla::Product->get_all)[0];
plan skip_all => 'BMO extension with default_security_group required'
  unless $test_product && $test_product->can('default_security_group');

# Set up as admin user
my $user = Bugzilla::User->check({id => 1});
Bugzilla->set_user($user);

my @products = Bugzilla::Product->get_all;
plan skip_all => 'Need at least 2 products' if @products < 2;

my $prod_a = $products[0];
my $prod_b = $products[1];

my $sec_group_b = eval { $prod_b->default_security_group };
plan skip_all => 'Target product needs a default security group'
  unless $sec_group_b;

my $dbh = Bugzilla->dbh;

# Helper: create a bug in $prod_a and place it directly into the given groups.
# We insert into bug_group_map directly to bypass the group-control permission
# checks of the normal create path -- we only care about the resulting group
# membership, which mirrors a bug that was secured into arbitrary groups.
my $bug_counter = 0;
sub make_bug_in_groups {
  my (@group_ids) = @_;
  my $bug = Bugzilla::Bug->create({
    short_desc   => 'Clone security test bug ' . ($bug_counter++) . " - $$",
    product      => $prod_a->name,
    component    => $prod_a->components->[0]->name,
    bug_type     => 'defect',
    bug_severity => 'normal',
    op_sys       => 'Unspecified',
    rep_platform => 'Unspecified',
    version      => $prod_a->versions->[0]->name,
  });
  $dbh->do('INSERT INTO bug_group_map (bug_id, group_id) VALUES (?, ?)',
    undef, $bug->id, $_)
    for @group_ids;

  # Re-fetch so groups_in reflects the direct membership changes.
  return Bugzilla::Bug->new($bug->id);
}

sub clone_groups_for {
  my ($bug, $target) = @_;
  my @groups = map { $_->name } @{$bug->groups_in};
  push(@groups, $bug->extra_security_groups_for_clone($target));
  return @groups;
}

# A non-default security group with no group_control_map entry for prod_b, so
# it is not valid there and would be silently dropped when cloning. This is
# the Bug 2049554 case (e.g. dom-core-security cloned out of Core).
my $dropped_group = Bugzilla::Group->create({
  name        => 'test-dropped-sec-' . $$,
  description => 'Temporary security group not valid in the target product',
  isbuggroup  => 1,
});

# A group that is valid in prod_b (othercontrol Shown), so it carries over
# when cloning there and nothing is dropped.
my $portable_group = Bugzilla::Group->create({
  name        => 'test-portable-sec-' . $$,
  description => 'Temporary group valid in the target product',
  isbuggroup  => 1,
});
$dbh->do(
  'INSERT INTO group_control_map (group_id, product_id, entry, membercontrol, othercontrol, canedit)
   VALUES (?, ?, 0, ?, ?, 0)',
  undef, $portable_group->id, $prod_b->id, CONTROLMAPSHOWN, CONTROLMAPSHOWN);

# ---- Cross-product clone of a bug whose group is dropped ----

{
  my $bug = make_bug_in_groups($dropped_group->id);

  my @bug_groups = map { $_->name } @{$bug->groups_in};
  ok(
    (grep { $_ eq $dropped_group->name } @bug_groups),
    "Bug is in the non-default security group (" . $dropped_group->name . ")"
  );

  my @clone_groups = clone_groups_for($bug, $prod_b);
  ok(
    (grep { $_ eq $sec_group_b } @clone_groups),
    "Clone adds the target default security group when a group is dropped ($sec_group_b)"
  );
}

# ---- Cross-product clone where every group carries over ----

{
  my $bug = make_bug_in_groups($portable_group->id);

  my @clone_groups = clone_groups_for($bug, $prod_b);
  ok(
    (grep { $_ eq $portable_group->name } @clone_groups),
    "Clone preserves a group that is valid in the target product"
  );
  ok(
    !(grep { $_ eq $sec_group_b } @clone_groups),
    "Clone does NOT add the target default security group when nothing is dropped"
  );
}

# ---- Mixed: one group dropped, one carried over ----
#
# Models a Core bug in both dom-core-security and mozilla-employee-confidential
# cloned into Firefox: the Core-specific group is dropped, the portable group
# carries over, and the target default is added as a fallback.

{
  my $bug = make_bug_in_groups($dropped_group->id, $portable_group->id);

  my @clone_groups = clone_groups_for($bug, $prod_b);
  ok(
    (grep { $_ eq $portable_group->name } @clone_groups),
    "Mixed clone preserves the portable group"
  );
  ok(
    (grep { $_ eq $sec_group_b } @clone_groups),
    "Mixed clone adds the target default security group ($sec_group_b)"
  );
}

# ---- Same-product clone adds nothing ----

{
  my $bug = make_bug_in_groups($dropped_group->id);
  my @extra = $bug->extra_security_groups_for_clone($prod_a);
  is(scalar(@extra), 0, "Same-product clone adds no extra security group");
}

# ---- Public bug clone adds nothing ----

{
  my $bug   = make_bug_in_groups();
  my @extra = $bug->extra_security_groups_for_clone($prod_b);
  is(scalar(@extra), 0, "Public bug clone does NOT get a security group");
}

# ---- Cleanup ----

$dbh->do('DELETE FROM bug_group_map WHERE group_id IN (?, ?)',
  undef, $dropped_group->id, $portable_group->id);
$dbh->do('DELETE FROM group_control_map WHERE group_id IN (?, ?)',
  undef, $dropped_group->id, $portable_group->id);
$dropped_group->remove_from_db();
$portable_group->remove_from_db();

done_testing();
