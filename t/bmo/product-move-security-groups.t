#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Test that moving a security bug to a different product via set_all() (which
# covers the REST API path) preserves the security intent by adding the target
# product's default security group (Bug 2038147).

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

my $test_product = (Bugzilla::Product->get_all)[0];
plan skip_all => 'BMO extension with default_security_group required'
  unless $test_product && $test_product->can('default_security_group');

my $user = Bugzilla::User->check({id => 1});
Bugzilla->set_user($user);

my @products = Bugzilla::Product->get_all;
plan skip_all => 'Need at least 2 products' if @products < 2;

my $prod_a = $products[0];
my $prod_b = $products[1];
my $dbh    = Bugzilla->dbh;

# Create isolated test groups, one per product, with no cross-product
# group_control_map entry. This guarantees the source group is invalid in
# the target product (so removal is testable) and vice-versa.
my $pid = $$;
my $group_a = Bugzilla::Group->create({
  name        => "test-sec-source-$pid",
  description => 'Temp source security group for Bug 2038147 test',
  isbuggroup  => 1,
});
my $group_b = Bugzilla::Group->create({
  name        => "test-sec-target-$pid",
  description => 'Temp target security group for Bug 2038147 test',
  isbuggroup  => 1,
});

# Wire each group into its product only.
$dbh->do(
  'INSERT IGNORE INTO group_control_map
     (group_id, product_id, entry, membercontrol, othercontrol, canedit)
   VALUES (?, ?, 0, 1, 0, 0)',
  undef, $group_a->id, $prod_a->id);
$dbh->do(
  'INSERT IGNORE INTO group_control_map
     (group_id, product_id, entry, membercontrol, othercontrol, canedit)
   VALUES (?, ?, 0, 1, 0, 0)',
  undef, $group_b->id, $prod_b->id);

# Save existing security group IDs so we can restore them.
my ($orig_sec_a) = $dbh->selectrow_array(
  'SELECT security_group_id FROM products WHERE id = ?', undef, $prod_a->id);
my ($orig_sec_b) = $dbh->selectrow_array(
  'SELECT security_group_id FROM products WHERE id = ?', undef, $prod_b->id);

$dbh->do('UPDATE products SET security_group_id = ? WHERE id = ?',
  undef, $group_a->id, $prod_a->id);
$dbh->do('UPDATE products SET security_group_id = ? WHERE id = ?',
  undef, $group_b->id, $prod_b->id);

# Add admin to both groups so set_all() permission checks pass.
$dbh->do(
  'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
   VALUES (?, ?, 0, 0)',
  undef, $user->id, $group_a->id);
$dbh->do(
  'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
   VALUES (?, ?, 0, 0)',
  undef, $user->id, $group_b->id);

# Invalidate both the request-level object cache and memcached (Product IS_CONFIG=1,
# so get_all and new({cache=>1}) both go through memcached). Without this, stale
# entries from previous tests cause product_obj->default_security_group to return
# the wrong group name and _target_security_group_for_move returns empty.
Bugzilla::Product->object_cache_clearall();
Bugzilla->memcached->clear({table => 'products', id => $prod_a->id});
Bugzilla->memcached->clear({table => 'products', id => $prod_b->id});
Bugzilla->memcached->clear_config();
$prod_a = Bugzilla::Product->new({id => $prod_a->id});
$prod_b = Bugzilla::Product->new({id => $prod_b->id});

my $sec_group_a = $prod_a->default_security_group;
my $sec_group_b = $prod_b->default_security_group;

isnt($sec_group_a, $sec_group_b,
  "Test groups are distinct ($sec_group_a vs $sec_group_b)");

# ---- Security bug: source group removed, target group added ----

my $sec_bug = Bugzilla::Bug->create({
  short_desc   => 'Test security move - Bug 2038147',
  product      => $prod_a->name,
  component    => $prod_a->components->[0]->name,
  bug_type     => 'defect',
  bug_severity => 'normal',
  op_sys       => 'Unspecified',
  rep_platform => 'Unspecified',
  version      => $prod_a->versions->[0]->name,
  groups       => [$sec_group_a],
});
ok($sec_bug->id, "Created security bug " . $sec_bug->id);

my @before_groups = map { $_->name } @{$sec_bug->groups_in};
ok((grep { $_ eq $sec_group_a } @before_groups),
  "Bug starts in source security group ($sec_group_a)");

$sec_bug->set_all({
  product   => $prod_b->name,
  component => $prod_b->components->[0]->name,
  version   => $prod_b->versions->[0]->name,
});
$sec_bug->update();

# Reload sec_bug after groups update
$sec_bug = Bugzilla::Bug->new({id => $sec_bug->id});

my @after_groups = map { $_->name } @{$sec_bug->groups_in};
ok(!(grep { $_ eq $sec_group_a } @after_groups),
  "Source security group ($sec_group_a) removed after product move");
ok((grep { $_ eq $sec_group_b } @after_groups),
  "Target security group ($sec_group_b) added after product move");

# ---- Security bug in a NON-default security group: target default still added ----
#
# Models a Core bug in dom-core-security (not Core's own default security group)
# moved to Firefox. The non-default group is dropped in the target, so the
# target's default security group must still be added so the bug stays
# restricted to the best of our ability (Bug 2049554, Bug 2038147).

my $nondefault_group = Bugzilla::Group->create({
  name        => "test-sec-nondefault-$pid",
  description => 'Temp non-default security group for Bug 2038147 test',
  isbuggroup  => 1,
});

# Valid in the source product only, so it is dropped when moving to the target.
$dbh->do(
  'INSERT IGNORE INTO group_control_map
     (group_id, product_id, entry, membercontrol, othercontrol, canedit)
   VALUES (?, ?, 0, 1, 0, 0)',
  undef, $nondefault_group->id, $prod_a->id);
$dbh->do(
  'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
   VALUES (?, ?, 0, 0)',
  undef, $user->id, $nondefault_group->id);

my $nd_bug = Bugzilla::Bug->create({
  short_desc   => 'Test non-default security move - Bug 2038147',
  product      => $prod_a->name,
  component    => $prod_a->components->[0]->name,
  bug_type     => 'defect',
  bug_severity => 'normal',
  op_sys       => 'Unspecified',
  rep_platform => 'Unspecified',
  version      => $prod_a->versions->[0]->name,
});

# Place the bug directly into the non-default group so it is NOT in the source
# product's own default security group -- the case Bug 2049554 addressed.
$dbh->do('INSERT INTO bug_group_map (bug_id, group_id) VALUES (?, ?)',
  undef, $nd_bug->id, $nondefault_group->id);
$nd_bug = Bugzilla::Bug->new({id => $nd_bug->id});

my @nd_before = map { $_->name } @{$nd_bug->groups_in};
ok((grep { $_ eq $nondefault_group->name } @nd_before),
  "Bug starts in a non-default security group (" . $nondefault_group->name . ")");
ok(!(grep { $_ eq $sec_group_a } @nd_before),
  "Bug is NOT in the source product's default security group ($sec_group_a)");

$nd_bug->set_all({
  product   => $prod_b->name,
  component => $prod_b->components->[0]->name,
  version   => $prod_b->versions->[0]->name,
});
$nd_bug->update();
$nd_bug = Bugzilla::Bug->new({id => $nd_bug->id});

my @nd_after = map { $_->name } @{$nd_bug->groups_in};
ok(!(grep { $_ eq $nondefault_group->name } @nd_after),
  "Non-default security group removed after product move");
ok((grep { $_ eq $sec_group_b } @nd_after),
  "Target security group ($sec_group_b) added even though bug was only in a non-default group");

# ---- Public bug moved cross-product should NOT gain a security group ----

my $pub_bug = Bugzilla::Bug->create({
  short_desc   => 'Test public move - Bug 2038147',
  product      => $prod_a->name,
  component    => $prod_a->components->[0]->name,
  bug_type     => 'defect',
  bug_severity => 'normal',
  op_sys       => 'Unspecified',
  rep_platform => 'Unspecified',
  version      => $prod_a->versions->[0]->name,
});

$pub_bug->set_all({
  product   => $prod_b->name,
  component => $prod_b->components->[0]->name,
  version   => $prod_b->versions->[0]->name,
});
$pub_bug->update();

my @pub_after = map { $_->name } @{$pub_bug->groups_in};
ok(!(grep { $_ eq $sec_group_b } @pub_after),
  "Public bug does NOT gain target security group ($sec_group_b) after product move");

# ---- Cleanup ----

$dbh->do('UPDATE products SET security_group_id = ? WHERE id = ?',
  undef, $orig_sec_a, $prod_a->id);
$dbh->do('UPDATE products SET security_group_id = ? WHERE id = ?',
  undef, $orig_sec_b, $prod_b->id);
Bugzilla::Product->object_cache_clearall();
Bugzilla->memcached->clear({table => 'products', id => $prod_a->id});
Bugzilla->memcached->clear({table => 'products', id => $prod_b->id});
Bugzilla->memcached->clear_config();
$dbh->do('DELETE FROM user_group_map WHERE group_id IN (?, ?, ?)',
  undef, $group_a->id, $group_b->id, $nondefault_group->id);
$dbh->do('DELETE FROM group_control_map WHERE group_id IN (?, ?, ?)',
  undef, $group_a->id, $group_b->id, $nondefault_group->id);
$dbh->do('DELETE FROM bug_group_map WHERE group_id IN (?, ?, ?)',
  undef, $group_a->id, $group_b->id, $nondefault_group->id);
$group_a->remove_from_db();
$group_b->remove_from_db();
$nondefault_group->remove_from_db();

done_testing();
