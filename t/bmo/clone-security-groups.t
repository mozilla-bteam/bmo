#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Test that cloning a security bug across products preserves security
# group defaults (Bug 2028240).

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

# Find two products. We need them to have different default security groups
# to test cross-product cloning. If they share the same group, create a
# second one.
my @products = Bugzilla::Product->get_all;
plan skip_all => 'Need at least 2 products' if @products < 2;

my $prod_a = $products[0];
my $prod_b = $products[1];

my $sec_group_a = eval { $prod_a->default_security_group };
my $sec_group_b = eval { $prod_b->default_security_group };

plan skip_all => 'Products need default security groups'
  unless $sec_group_a && $sec_group_b;

# If both products share the same security group, create a test group
# and assign it to product B so we can test the cross-product mapping.
my $created_group;
if ($sec_group_a eq $sec_group_b) {
  my $dbh = Bugzilla->dbh;
  $created_group = Bugzilla::Group->create({
    name        => 'test-security-clone-' . $$,
    description => 'Temporary group for clone security test',
    isbuggroup  => 1,
  });
  # Assign to product B
  $dbh->do(
    'UPDATE products SET security_group_id = ? WHERE id = ?',
    undef, $created_group->id, $prod_b->id);
  # Re-fetch product to pick up the new security_group_id
  $prod_b = Bugzilla::Product->new({id => $prod_b->id});

  $sec_group_b = $prod_b->default_security_group;

  # Make sure the user is in the new group
  $dbh->do(
    'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type) VALUES (?, ?, 0, 0)',
    undef, $user->id, $created_group->id);

  # Also add group to product's group controls so bugs can use it
  $dbh->do(
    'INSERT IGNORE INTO group_control_map (group_id, product_id, entry, membercontrol, othercontrol, canedit)
     VALUES (?, ?, 0, 1, 0, 0)',
    undef, $created_group->id, $prod_b->id);
}

isnt($sec_group_a, $sec_group_b,
  "Test products have different security groups ($sec_group_a vs $sec_group_b)");

# Create a security bug in product A
my $bug = Bugzilla::Bug->create({
  short_desc   => 'Test security clone - Bug 2028240',
  product      => $prod_a->name,
  component    => $prod_a->components->[0]->name,
  bug_type     => 'defect',
  bug_severity => 'normal',
  op_sys       => 'Unspecified',
  rep_platform => 'Unspecified',
  version      => $prod_a->versions->[0]->name,
  groups       => [$sec_group_a],
});
ok($bug->id, "Created security bug " . $bug->id);

my @bug_groups = map { $_->name } @{$bug->groups_in};
ok((grep { $_ eq $sec_group_a } @bug_groups),
  "Bug is in source security group ($sec_group_a)");

# ---- Test the clone logic via Bugzilla::Bug method ----

# Cross-product clone: bug from prod_a, target is prod_b
my @clone_groups = map { $_->name } @{$bug->groups_in};
push(@clone_groups, $bug->extra_security_groups_for_clone($prod_b));

ok((grep { $_ eq $sec_group_b } @clone_groups),
  "Cross-product clone adds target security group ($sec_group_b)");
ok((grep { $_ eq $sec_group_a } @clone_groups),
  "Cross-product clone preserves source security group ($sec_group_a)");

# ---- Same-product clone should not duplicate ----

my @same_groups = map { $_->name } @{$bug->groups_in};
push(@same_groups, $bug->extra_security_groups_for_clone($prod_a));

is(scalar(grep { $_ eq $sec_group_a } @same_groups), 1,
  "Same-product clone doesn't duplicate security group");

# ---- Non-security bug should NOT get security group ----

my $public_bug = Bugzilla::Bug->create({
  short_desc   => 'Test public clone - Bug 2028240',
  product      => $prod_a->name,
  component    => $prod_a->components->[0]->name,
  bug_type     => 'defect',
  bug_severity => 'normal',
  op_sys       => 'Unspecified',
  rep_platform => 'Unspecified',
  version      => $prod_a->versions->[0]->name,
});

my @pub_groups = map { $_->name } @{$public_bug->groups_in};
push(@pub_groups, $public_bug->extra_security_groups_for_clone($prod_b));

ok(!(grep { $_ eq $sec_group_b } @pub_groups),
  "Public bug clone does NOT get target security group");

# ---- Cleanup ----

if ($created_group) {
  my $dbh = Bugzilla->dbh;
  # Restore product B's original security group
  my $orig_group = Bugzilla::Group->new({name => $sec_group_a});
  $dbh->do('UPDATE products SET security_group_id = ? WHERE id = ?',
    undef, $orig_group->id, $prod_b->id);
  $dbh->do('DELETE FROM user_group_map WHERE group_id = ?',
    undef, $created_group->id);
  $dbh->do('DELETE FROM group_control_map WHERE group_id = ?',
    undef, $created_group->id);
  $created_group->remove_from_db();
}

done_testing();
