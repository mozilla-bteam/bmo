#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;

# List of products and components that use a bug type other than "defect"
use constant MIGRATION_MAP => (
  ['Air Mozilla', 'Events', 'task'],
  ['AUS Graveyard', 'Administration', 'task'],
  ['Bugzilla', 'Administration', 'task'],
  ['bugzilla.mozilla.org', 'Administration', 'task'],
  ['bugzilla.mozilla.org', 'Bulk Bug Edit Requests', 'task'],
  ['bugzilla.mozilla.org', 'Graveyard Tasks', 'task'],
  ['Cloud Services', 'Operations', 'task'],
  ['Cloud Services', 'Operations: Activedata', 'task'],
  ['Cloud Services', 'Operations: AMO', 'task'],
  ['Cloud Services', 'Operations: Antenna', 'task'],
  ['Cloud Services', 'Operations: Autopush', 'task'],
  ['Cloud Services', 'Operations: AWS Account Request', 'task'],
  ['Cloud Services', 'Operations: Bzetl', 'task'],
  ['Cloud Services', 'Operations: Delivery Console', 'task'],
  ['Cloud Services', 'Operations: Deployment Requests', 'task'],
  ['Cloud Services', 'Operations: LandoAPI', 'task'],
  ['Cloud Services', 'Operations: LandoUI', 'task'],
  ['Cloud Services', 'Operations: Marketplace', 'task'],
  ['Cloud Services', 'Operations: Metrics/Monitoring', 'task'],
  ['Cloud Services', 'Operations: Normandy', 'task'],
  ['Cloud Services', 'Operations: Pageshot', 'task'],
  ['Cloud Services', 'Operations: Phabricator', 'task'],
  ['Cloud Services', 'Operations: Product Delivery', 'task'],
  ['Cloud Services', 'Operations: Sentry', 'task'],
  ['Cloud Services', 'Operations: Shavar', 'task'],
  ['Cloud Services', 'Operations: Storage', 'task'],
  ['Community Building', '', 'task'],
  ['Conduit', 'Administration', 'task'],
  ['Data & BI Services Team', '', 'task'],
  ['Data & BI Services Team Graveyard', '', 'task'],
  ['Data Compliance', '', 'task'],
  ['Data Science', '', 'task'],
  ['Developer Engagement', '', 'task'],
  ['Developer Services', 'General', 'task'],
  ['developer.mozilla.org', 'Account Help', 'task'],
  ['developer.mozilla.org', 'Administration', 'task'],
  ['developer.mozilla.org', 'Events', 'task'],
  ['developer.mozilla.org', 'Marketing', 'task'],
  ['developer.mozilla.org', 'User management', 'task'],
  ['Enterprise Information Security', '', 'task'],
  ['Enterprise Information Security Graveyard', '', 'task'],
  ['Finance', '', 'task'],
  ['Firefox Build System', 'Task Configuration', 'task'],
  ['FSA Graveyard', '', 'task'],
  ['Infrastructure & Operations', '', 'task'],
  ['Infrastructure & Operations Graveyard', '', 'task'],
  ['Internet Public Policy', '', 'task'],
  ['Legal Graveyard', '', 'task'],
  ['Localization Infrastructure and Tools', 'Administration / Setup', 'task'],
  ['Marketing', '', 'task'],
  ['Mozilla Foundation', '', 'task'],
  ['Mozilla Foundation Communications', '', 'task'],
  ['Mozilla Foundation Operations', '', 'task'],
  ['Mozilla Grants', '', 'task'],
  ['Mozilla Metrics', 'Metrics Operations', 'task'],
  ['Mozilla Reps', '', 'task'],
  ['Mozilla Reps Graveyard', 'Community IT Requests', 'task'],
  ['Mozilla Reps Graveyard', 'Planning', 'task'],
  ['mozilla.org', '', 'task'],
  ['mozilla.org Graveyard', '', 'task'],
  ['Participation Infrastructure', 'Account Help', 'task'],
  ['Participation Infrastructure', 'API Requests', 'task'],
  ['Participation Infrastructure', 'Community Ops', 'task'],
  ['Participation Infrastructure', 'Data Complaints', 'task'],
  ['Privacy Graveyard', '', 'task'],
  ['Recruiting', '', 'task'],
  ['Snippets', 'Campaign', 'task'],
  ['Snippets', 'Surveys', 'task'],
  ['Socorro', '', 'task'],
  ['support.mozilla.org', 'Army of Awesome', 'task'],
  ['support.mozilla.org', 'Code Quality', 'task'],
  ['support.mozilla.org', 'Forum', 'task'],
  ['support.mozilla.org', 'Knowledge Base Articles', 'task'],
  ['support.mozilla.org', 'Knowledge Base Content', 'task'],
  ['support.mozilla.org', 'Knowledge Base Software', 'task'],
  ['support.mozilla.org', 'Lithium Migration', 'task'],
  ['support.mozilla.org', 'Localization', 'task'],
  ['support.mozilla.org', 'Mobile', 'task'],
  ['support.mozilla.org', 'Questions', 'task'],
  ['support.mozilla.org', 'Users and Groups', 'task'],
  ['Taskcluster', 'Operations and Service Requests', 'task'],
  ['Websites', 'Web Analytics', 'task'],
  ['Firefox Build System', 'Mach Core', 'enhancement'],
  ['support.mozilla.org - Lithium', 'Feature request', 'enhancement'],
);

my $dbh = Bugzilla->dbh;

foreach my $target (@MIGRATION_MAP) {
  my ($product, $component, $type) = @$target;

  $dbh->bz_start_transaction;

  # Select bugs in the product (and component)
  my $bug_ids = $dbh->selectcol_arrayref(
    'SELECT bug_id FROM bugs AS bug
      JOIN products AS product ON bug.product_id = product.id
      JOIN components AS component ON bug.component_id = component.id
      WHERE product.name = ?' . ($component ? ' AND component.name = ?' : ''),
    undef, ($component ? ($product, $component) : ($product)));

  # Set type on these bugs
  # Since it's a silent migration, we don't update the timestamp
  $dbh->do('UPDATE bugs SET bug_type = ?
    WHERE ' . $dbh->sql_in('bug_id', $bug_ids), undef, ($type));

  # Select components
  my $comp_ids = $dbh->selectcol_arrayref(
    'SELECT component.id FROM components as component
      JOIN products AS product ON component.id = product.id
      WHERE product.name = ?' . ($component ? ' AND component.name = ?' : ''),
    undef, ($component ? ($product, $component) : ($product)));

  # Set default bug type on these components
  $dbh->do('UPDATE components SET default_bug_type = ?
    WHERE ' . $dbh->sql_in('id', $comp_ids), undef, ($type));

  $dbh->bz_commit_transaction;
}

$dbh->bz_start_transaction;

# Finally, disable the "enhancement" severity
$dbh->do('UPDATE bug_severity SET isactive = 0 WHERE value = "enhancement"');

$dbh->bz_commit_transaction;

Bugzilla->memcached->clear_all();
