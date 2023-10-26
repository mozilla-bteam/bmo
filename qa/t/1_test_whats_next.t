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

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');

# S1 bugs assigned to you
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for s1 bugs assigned to you');
$sel->select_ok('component',    'General');
$sel->select_ok('bug_severity', 'S1');
$sel->select_ok('bug_status',   'ASSIGNED');
$sel->type_ok('assigned_to', $config->{admin_user_login});
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# sec-crit bugs assigned to you (private bug)
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for sec-critical bugs assigned to you');
$sel->select_ok('component', 'General');
$sel->type_ok('keywords', 'sec-critical');
$sel->select_ok('bug_status', 'ASSIGNED');
$sel->type_ok('assigned_to', $config->{admin_user_login});
$sel->check_ok('//input[@name="groups" and @value="Master"]');
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# Bugs that are needinfo? you and are marked as being tracked against
# or blocking the current nightly, beta, or release versions.
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc',
  'test bug for needinfo you tracked against nightly beta release');
$sel->select_ok('component', 'General');
$sel->click_ok('//input[@value="Set bug flags"]');
$sel->select_ok('cf_tracking_firefox111', 'blocking');
$sel->type_ok('needinfo_from', $config->{admin_user_login});
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# S2 bugs assigned to you
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for s2 bugs assigned to you');
$sel->select_ok('component',    'General');
$sel->select_ok('bug_severity', 'S2');
$sel->select_ok('bug_status',   'ASSIGNED');
$sel->type_ok('assigned_to', $config->{admin_user_login});
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# sec-high bugs assigned to you (private bug)
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for sec-high bugs assigned to you');
$sel->select_ok('component', 'General');
$sel->type_ok('keywords', 'sec-high');
$sel->select_ok('bug_status', 'ASSIGNED');
$sel->type_ok('assigned_to', $config->{admin_user_login});
$sel->check_ok('//input[@name="groups" and @value="Master"]');
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');

# Regressions
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for regressions assigned to you');
$sel->select_ok('component', 'General');
$sel->type_ok('keywords', 'regression');
$sel->select_ok('bug_status', 'ASSIGNED');
$sel->type_ok('assigned_to', $config->{admin_user_login});
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');
logout($sel);

# Other needinfos (needinfos for me but not set by me)
log_in($sel, $config, 'QA_Selenium_TEST');
file_bug_in_product($sel, 'Firefox', undef, 'legacy');
$sel->type_ok('short_desc', 'test bug for other needinfos not set by you');
$sel->select_ok('component', 'General');
$sel->type_ok('needinfo_from', $config->{admin_user_login});
$sel->click_ok('commit');
$sel->is_text_present_ok('has been added to the database', 'Bug created');
logout($sel);

# Open the whats next report as admin
log_in($sel, $config, 'admin');
$sel->open_ok('/page.cgi?id=whats_next.html');
$sel->title_is('What should I work on next?');

# Check for the existence of rows for each of the tables that we created bugs for
$sel->is_text_present_ok(
  'test bug for s1 bugs assigned to you',
  'test bug for s1 bugs assigned to you'
);
$sel->is_text_present_ok(
  'test bug for sec-critical bugs assigned to you',
  'test bug for sec-critical bugs assigned to you'
);
$sel->is_text_present_ok(
  'test bug for needinfo you tracked against nightly beta release',
  'test bug for needinfo you tracked against nightly beta release'
);
$sel->is_text_present_ok(
  'test bug for s2 bugs assigned to you',
  'test bug for s2 bugs assigned to you'
);
$sel->is_text_present_ok(
  'test bug for sec-high bugs assigned to you',
  'test bug for sec-high bugs assigned to you'
);
$sel->is_text_present_ok(
  'test bug for regressions assigned to you',
  'test bug for regressions assigned to you'
);
$sel->is_text_present_ok(
  'test bug for other needinfos not set by you',
  'test bug for other needinfos not set by you'
);

logout($sel);

# Open whats next report as qa user and make sure
# private bugs filed by admin user are not visible but
# others are.
log_in($sel, $config, 'QA_Selenium_TEST');
$sel->open_ok('/page.cgi?id=whats_next.html');
$sel->title_is('What should I work on next?');
$sel->type_ok('who', $config->{admin_user_login});
$sel->click_ok('run');
$sel->title_is('What should I work on next?');

$sel->is_text_present_ok(
  'test bug for s1 bugs assigned to you',
  'test bug for s1 bugs assigned to you'
);
ok(
  !$sel->is_text_present('test bug for sec-critical bugs assigned to you'),
  'test bug for sec-critical bugs assigned to you (not present)'
);
ok(
  !$sel->is_text_present('test bug for sec-high bugs assigned to you'),
  'test bug for sec-high bugs assigned to you (not present)'
);

logout($sel);

done_testing;
