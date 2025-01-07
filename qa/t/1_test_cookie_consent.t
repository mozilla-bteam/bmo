# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is 'Incompatible With Secondary Licenses', as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More 'no_plan';

use List::Util qw(first none);
use QA::Util;

my ($sel, $config) = get_selenium();

# Turn on cookie consent
log_in($sel, $config, 'admin');
set_parameters($sel,
  {'Administrative Policies' => {'cookie_consent_enabled-on' => undef}});

# Accept all cookies for admin user
$sel->click_ok('moz-consent-banner-button-accept');

# Make sure that a 'moz-consent-pref' cookie was set to yes
my $cookies     = $sel->driver->get_all_cookies;
my $pref_cookie = first { $_->{name} eq 'moz-consent-pref' } @{$cookies};
ok($pref_cookie && $pref_cookie->{value} eq 'yes',
  'Consent cookie set to yes properly');

# Create a test bug
file_bug_in_product($sel, 'TestProduct');
my $bug_summary = 'Cookie consent test bug';
$sel->type_ok('short_desc', $bug_summary);
my $bug1_id = create_bug($sel, $bug_summary);

# Run a buglist query to set a cookie such as LASTORDER which is non-essential
open_advanced_search_page($sel);
$sel->type_ok('short_desc', 'Cookie consent test bug');
$sel->select_ok('order', 'label=Bug Number', 'Select order by bug number');
$sel->click_ok('Search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Bug List');
$sel->is_text_present_ok('One bug found');
$sel->is_text_present_ok('Cookie consent test bug');

$cookies = $sel->driver->get_all_cookies;
my $last_order_cookie = first { $_->{name} eq 'LASTORDER' } @{$cookies};
ok($last_order_cookie, 'Last order cookie set properly');

# Change cookie preferences to reject
$sel->click_ok('header-account-menu-button');
$sel->click_ok('//a[./span[@data-icon="cookie"]]');
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is('Cookie Settings');
$sel->click_ok('cookie-radio-preference-no');
$sel->click_ok('cookie-consent-save');
$sel->is_text_present_ok('Your Cookie settings have been updated');

# Clear all cookies except the consent cookie and login stuff
$cookies = $sel->driver->get_all_cookies;
foreach my $cookie (@{$cookies}) {
  my $name = $cookie->{name};
  unless ($name eq 'Bugzilla_login'
    || $name eq 'Bugzilla_logincookie'
    || $name eq 'moz-consent-pref')
  {
    $sel->driver->delete_cookie_named($name);
  }
}

# Verify that LASTORDER and COLUMNLIST are no longer set
open_advanced_search_page($sel);
$sel->type_ok('short_desc', 'Cookie consent test bug');
$sel->select_ok('order', 'label=Bug Number', 'Select order by bug number');
$sel->click_ok('Search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Bug List');
$sel->is_text_present_ok('One bug found');
$sel->is_text_present_ok('Cookie consent test bug');

$cookies = $sel->driver->get_all_cookies;
$last_order_cookie = first { $_->{name} eq 'LASTORDER' } @{$cookies};
ok(!$last_order_cookie, 'Last order cookie not set properly');

# Logout and clear all cookies. Then we will reject all cookies and verify
logout($sel);
$sel->driver->delete_all_cookies();
$sel->open_ok('/home', 'Go to home page');
$sel->click_ok('moz-consent-banner-button-reject');

log_in($sel, $config, 'admin');
open_advanced_search_page($sel);
$sel->type_ok('short_desc', 'Cookie consent test bug');
$sel->select_ok('order', 'label=Bug Number', 'Select order by bug number');
$sel->click_ok('Search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Bug List');
$sel->is_text_present_ok('One bug found');
$sel->is_text_present_ok('Cookie consent test bug');

$cookies = $sel->driver->get_all_cookies;
$last_order_cookie = first { $_->{name} eq 'LASTORDER' } @{$cookies};
ok(!$last_order_cookie, 'Last order cookie not set properly');

## Turn off cookie consent
set_parameters($sel,
  {'Administrative Policies' => {'cookie_consent_enabled-off' => undef}});
logout($sel);

done_testing;

1;
