# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../.. ../../local/lib/perl5);

use Bugzilla;
BEGIN { Bugzilla->extensions }

use QA::Util;
use Test::More "no_plan";

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Webhooks' => {
      'webhooks_enabled-on' => undef,
      'webhooks_group'      => {type => 'select', value => 'editbugs'},
    }
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

# Login as editbugs user and add two webhooks
# * One webhook connects without authentication
# * The other uses an API key header to authenticate
log_in($sel, $config, 'editbugs');
$sel->click_ok('header-account-menu-button');
$sel->click_ok('link=Preferences');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('User Preferences', 'User preferences');
$sel->click_ok('link=Webhooks');

# Name is required
$sel->click_ok('add_webhook');
$sel->title_is('Define a name', 'Define a name');
$sel->go_back_ok();
$sel->type_ok('name', 'Webhook (no auth)');
$sel->type_ok('url',  'http://externalapi.test/webhooks/test/noauth');
$sel->check_ok('change_event');
$sel->check_ok('comment_event');
$sel->select_ok('product', 'value=Firefox');
$sel->click_ok('add_webhook');
$sel->is_text_present_ok('Webhook (no auth)');
$sel->is_text_present_ok('change,comment');
$sel->type_ok('name', 'Webhook (with auth)');
$sel->type_ok('url',  'http://externalapi.test/webhooks/test/withauth');
$sel->check_ok('create_event');
$sel->check_ok('attachment_event');
$sel->select_ok('product', 'value=Firefox');
$sel->type_ok('api_key_header', 'Authorization');
$sel->type_ok('api_key_value',
  'Token zQ5TSBzq7tTZMtKYq9K1ZqJMjifKx3cPL7pIGk9Q');
$sel->click_ok('add_webhook');
$sel->is_text_present_ok('Webhook (with auth)');
$sel->is_text_present_ok('create,attachment');
$sel->is_text_present_ok('Token zQ5TSBzq7tTZMtKYq9K1ZqJMjifKx3cPL7pIGk9Q');

# File a new bug in the Firefox product
file_bug_in_product($sel, 'Firefox');
my $bug_summary = 'Test bug for webhooks';
$sel->type_ok('short_desc', $bug_summary);
$sel->type_ok('comment',    $bug_summary);
my $bug_id = create_bug($sel, $bug_summary);
logout($sel);

# Give run push extension to pick up the new events
Bugzilla->push_ext->push();

# Check log to see if webhooks process
log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok('link=Log');
$sel->title_is('Push Administration: Logs', 'Push logs');
$sel->is_text_present_ok('Webhook_1', 'First webhook executed');
$sel->is_text_present_ok('Webhook_2', 'Second webhook executed');
ok(!$sel->is_text_present('ERROR'), 'ERROR message not present');

set_parameters($sel, {'Webhooks' => {'webhooks_enabled-off' => undef,}});
logout($sel);

done_testing();

1;
