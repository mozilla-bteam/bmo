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
use lib qw(. lib local/lib/perl5 qa/t/lib);

use Bugzilla;
BEGIN { Bugzilla->extensions }

use Mojo::Util qw(dumper);
use QA::Util;
use Test::More 'no_plan';
use Test::Mojo;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Webhooks' => {
      'webhooks_enabled-on' => undef,
      'webhooks_group'      => {type => 'select', value => 'editbugs'},
    },
    'Jira Webhook Sync' => {
      'jira_webhook_sync_hostname' => {type => 'text', value => 'externalapi.test'},
      'jira_webhook_sync_config'   => {
        type  => 'text',
        value => '{"BZFF": {"product": "Firefox", "component": "General"}}'
      },
      'jira_webhook_sync_project_keys' => {type => 'text', value => '["BZFF"]'},
    },
  }
);

# Enable global push daemon support
go_to_admin($sel);
$sel->click_ok('link=Configuration');
$sel->title_is('Push Administration: Configuration', 'Push configuration');
$sel->select_ok('global_enabled', 'label=Enabled');
$sel->click_ok('//input[@type="submit" and @value="Submit Changes"]');
$sel->is_text_present_ok('Changes to the configuration have been saved');
logout($sel);

# Login as editbugs user add a new webhook
log_in($sel, $config, 'editbugs');
$sel->click_ok('header-account-menu-button');
$sel->click_ok("//a[./span[contains(text(), 'Preferences')]]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('User Preferences', 'User preferences');
$sel->click_ok('link=Webhooks');
$sel->type_ok('name', 'Jira Sync Webhook');
$sel->type_ok('url',  'http://externalapi.test:8001/webhooks/store_payload');
$sel->check_ok('create_event');
$sel->check_ok('change_event');
$sel->select_ok('product', 'value=Firefox');
$sel->click_ok('add_webhook');
$sel->is_text_present_ok('Jira Sync Webhook');
$sel->is_text_present_ok('create');

# File a new bug in the Firefox product and General component
# The BZFF whiteboard tag should be added to the webhook payload
file_bug_in_product($sel, 'Firefox');
my $bug_summary_1 = 'Test bug for webhooks 1';
$sel->select_ok('component', 'value=General');
$sel->type_ok('short_desc', $bug_summary_1);
$sel->type_ok('comment',    $bug_summary_1);
my $bug_id_1 = create_bug($sel, $bug_summary_1);

# Give run push extension to pick up the new events
Bugzilla->push_ext->push();

# Call the endpoint to get back the json that was sent
my $t = Test::Mojo->new();
$t->get_ok('http://externalapi.test:8001/webhooks/last_payload')
  ->status_is(200)
  ->json_is('/bug/id',         $bug_id_1)
  ->json_is('/bug/summary',    $bug_summary_1)
  ->json_is('/bug/product',    'Firefox')
  ->json_is('/bug/component',  'General')
  ->json_is('/bug/whiteboard', '[BZFF]');

# File a new bug in the Firefox product and Install component
# The BZFF whiteboard tag should not be added to the webhook payload
file_bug_in_product($sel, 'Firefox');
my $bug_summary_2 = 'Test bug for webhooks 2';
$sel->select_ok('component', 'value=Installer');
$sel->type_ok('short_desc', $bug_summary_2);
$sel->type_ok('comment',    $bug_summary_2);
my $bug_id_2 = create_bug($sel, $bug_summary_2);
logout($sel);

# Give run push extension to pick up the new events
Bugzilla->push_ext->push();

# Call the endpoint to get back the json that was sent
$t->get_ok('http://externalapi.test:8001/webhooks/last_payload')
  ->status_is(200)
  ->json_is('/bug/id',         $bug_id_2)
  ->json_is('/bug/summary',    $bug_summary_2)
  ->json_is('/bug/product',    'Firefox')
  ->json_is('/bug/component',  'Installer')
  ->json_is('/bug/whiteboard', '');

# To test the jira mapping table feature, we will call the REST API and
# add the see also value as if JBI itself had performed the operation.
# After we add the see also value, we will get result back to make
# sure the actual see also was not added to the bug in the changes.
# We also need to change some other arbitrary field so that the
# bug is updated and the webhook is triggered.
# Then we look again at the last payload from the webhook, which should
# contain the see also value that was generated from the mapping table.
my $jira_url = 'https://externalapi.test/browse/BZFF-100';
my $update   = {see_also => {add => [$jira_url]}, 'priority' => 'P2'};
$t->put_ok($config->{browser_url}
    . "/rest/bug/$bug_id_1"                                 =>
    {'X-Bugzilla-API-Key' => $config->{admin_user_api_key}} => json => $update)
  ->status_is(200)
  ->json_is('/bugs/0/id', $bug_id_1)
  ->json_hasnt('/bugs/0/changes/see_also');

# Give run push extension to pick up the new events
Bugzilla->push_ext->push();

# Call the endpoint to get back the json that was sent
$t->get_ok('http://externalapi.test:8001/webhooks/last_payload')
  ->status_is(200)
  ->json_is('/bug/id',         $bug_id_1)
  ->json_is('/bug/summary',    $bug_summary_1)
  ->json_is('/bug/product',    'Firefox')
  ->json_is('/bug/component',  'General')
  ->json_is('/bug/whiteboard', '[BZFF]')
  ->json_is('/bug/see_also/0', $jira_url);

# Turn off webhooks and jira sync.
log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Webhooks'          => {'webhooks_enabled-off' => undef,},
    'Jira Webhook Sync' =>
      {'jira_webhook_sync_hostname' => {type => 'text', value => ''},},
  }
);
logout($sel);

done_testing();

1;
