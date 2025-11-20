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
use lib qw(. lib local/lib/perl5 t);

use Test::More 'no_plan';

use Bugzilla;

use ok 'Bugzilla::Extension::JiraWebhookSync::JiraBugMap';

# Unit tests for extract_jira_info method
local Bugzilla->params->{jira_webhook_sync_project_keys} = '["FOO","BAZ"]';

# Success
my ($jira_id, $project_key)
  = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->extract_jira_info(
  'https://externalapi.test/browse/FOO-100');
ok(
  $jira_id eq 'FOO-100' && $project_key eq 'FOO',
  'Correct Jira ID and Project Key extracted'
);
($jira_id, $project_key)
  = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->extract_jira_info(
  'https://externalapi.test/browse/BAZ-300');
ok(
  $jira_id eq 'BAZ-300' && $project_key eq 'BAZ',
  'Correct Jira ID and Project Key extracted'
);

# Failed
($jira_id, $project_key)
  = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->extract_jira_info(
  'https://externalapi.test/browse/FOO-100/some/more/path');
ok(!defined $jira_id && !defined $project_key,
  'No Jira ID or Project Key extracted for improperly formatted url');
($jira_id, $project_key)
  = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->extract_jira_info(
  'https://externalapi.test/browse/BAR-100');
ok(!defined $jira_id && !defined $project_key,
  'No Jira ID or Project Key extracted for wrong project key');

done_testing();
