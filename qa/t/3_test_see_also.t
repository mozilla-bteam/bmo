# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'editbugs');

# Valid external URL
file_bug_in_product($sel, 'TestProduct', undef, 'legacy');
$sel->type_ok(
  'see_also',
  'https://bugzilla-dev.allizom.org',
  'Set the see also field to an external URL'
);
$sel->type_ok('short_desc', 'Test for See Also');
$sel->type_ok('comment',    'This is a test to check see also field.');
$sel->click_ok('commit');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Valid local bug id
file_bug_in_product($sel, 'TestProduct', undef, 'legacy');
$sel->type_ok('see_also', $bug1_id,
  'Set the see also field to an internal bug id');
$sel->type_ok('short_desc', 'Test for See Also');
$sel->type_ok('comment',    'This is a test to check see also field.');
$sel->click_ok('commit');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Invalid bug id
go_to_bug($sel, $bug2_id);
$sel->type_ok('see_also', 'this is not a bug id or url');
$sel->click_ok('bottom-save-btn');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Invalid Bug ID');

# Invalid external URL
go_to_bug($sel, $bug2_id);
$sel->type_ok('see_also', 'https:///index.html');
$sel->click_ok('bottom-save-btn');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is('Invalid Bug URL');

logout($sel);
