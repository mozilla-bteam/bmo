# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../.. ../../local/lib/perl5);

use Cache::Memcached::Fast;
use QA::Util;
use Test::Mojo;
use Test::More "no_plan";

my ($sel, $config) = get_selenium();

my $t = Test::Mojo->new;
$t->ua->max_redirects(1);

# Turn on 'rate limiting'.

log_in($sel, $config, 'admin');
set_parameters(
  $sel,
  {
    'Administrative Policies' => {
      'rate_limit_active-on' => undef,
      'rate_limit_rules'     => {
        type  => 'text',
        value =>
          '{"get_attachments":[5,100],"get_comments":[5,100],"get_bug":[5,100],"show_bug":[5,100],"github":[5,100],"webpage_errors":[5,100], "token":[5,100], "api_key":[5,100], "username_password":[3,100]}'
      }
    }
  }
);
file_bug_in_product($sel, 'TestProduct');
my $bug_summary = 'Test bug for rate limiting';
$sel->type_ok('short_desc', $bug_summary);
$sel->type_ok('comment',    $bug_summary);
my $bug_id = create_bug($sel, $bug_summary);
logout($sel);

# RATE LIMITING TESTS

# Accessing show_bug.cgi as anonymous user should rate limit

# Load the same bug 5 times as anonymous user
for (1 .. 5) {
  $sel->open_ok("show_bug.cgi?id=$bug_id", "Load bug $bug_id");
  $sel->title_like(qr/\d+ \S $bug_summary/, 'Bug successfully loaded');
}

# Next one should be blocked by rate limiting
$sel->open_ok("show_bug.cgi?id=$bug_id", "Load bug $bug_id");
$sel->title_like(qr/Rate Limit Exceeded/, 'Rate Limit Exceeded');

clear_memcache();    # So we can connect again

# Rate limiting show_bug.cgi as logged in user should not rate limit

# Load the same bug 5 times as logged in user
log_in($sel, $config, 'admin');

for (1 .. 5) {
  $sel->open_ok("show_bug.cgi?id=$bug_id", "Load bug $bug_id");
  $sel->title_like(qr/\d+ \S $bug_summary/, 'Bug successfully loaded');
}

# Next one should not be blocked by rate limiting
$sel->open_ok("show_bug.cgi?id=$bug_id", "Load bug $bug_id");
$sel->title_like(qr/\d+ \S $bug_summary/,
  'Bug successfully loaded (not rate limited)');
logout($sel);

clear_memcache();    # So we can connect again

# Rate limiting get bug via REST API

# Load the same bug 5 times as anonymous user
for (1 .. 5) {
  $t->get_ok($config->{browser_url} . "/rest/bug/$bug_id")->status_is(200)
    ->json_is('/bugs/0/summary' => $bug_summary);
}

# Next one should be blocked by rate limiting
$t->get_ok($config->{browser_url} . "/rest/bug/$bug_id")->status_is(400)
  ->json_like('/message' => qr/You have exceeded the rate limit/);

clear_memcache();    # So we can connect again

# Turn rate limiting off
log_in($sel, $config, 'admin');
set_parameters($sel,
  {'Administrative Policies' => {'rate_limit_active-off' => undef,}});
logout($sel);

done_testing();

sub clear_memcache {
  Cache::Memcached::Fast->new({
    servers   => [$ENV{BMO_memcached_servers}],
    namespace => $ENV{BMO_memcached_namespace},
  })->flush_all;
}

1;
