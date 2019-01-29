# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla;
use Bugzilla::Constants;
BEGIN { Bugzilla->extensions };
use Test2::V0;
use Test2::Tools::Mock qw(mock mock_accessor);
use Test2::Tools::Exception qw(dies lives);
use ok 'Bugzilla::Search::Quicksearch';

my $CGI = mock 'Bugzilla::CGI' => (
  add_constructor => [
    fake_new => 'hash',
  ]
);
my $cgi;
my $Bugzilla = mock 'Bugzilla' => (
  override => [
    cgi => sub { return $cgi },
  ]
);
Bugzilla->usage_mode(USAGE_MODE_MOJO);

$cgi = Bugzilla::CGI->fake_new();
like(dies { quicksearch(undef) }, qr/buglist_parameters_required/, "Got right exception");

$cgi = Bugzilla::CGI->fake_new();
like(dies { quicksearch('') }, qr/buglist_parameters_required/, "Got right exception");

$cgi = Bugzilla::CGI->fake_new();
quicksearch("summary:batman OR summary:robin");
is(
  {$cgi->Vars},
  {
    'bug_status' => ['UNCONFIRMED', 'CONFIRMED', 'IN_PROGRESS'],
    'field0-0-0' => 'short_desc',
    'field0-0-1' => 'short_desc',
    'type0-0-0'  => 'substring',
    'type0-0-1'  => 'substring',
    'value0-0-0' => 'batman',
    'value0-0-1' => 'robin',
  },
  "or search checks out"
);

$cgi = Bugzilla::CGI->fake_new();
quicksearch("summary:batman AND summary:robin");
is(
  {$cgi->Vars},
  {
    'bug_status' => ['UNCONFIRMED', 'CONFIRMED', 'IN_PROGRESS'],
    'field0-0-0' => 'short_desc',
    'field1-0-0' => 'short_desc',
    'type0-0-0'  => 'substring',
    'type1-0-0'  => 'substring',
    'value0-0-0' => 'batman',
    'value1-0-0' => 'robin',
  },
  "and search checks out"
);

$cgi = Bugzilla::CGI->fake_new();
quicksearch("ALL summary:batman AND summary:robin");
is(
  {$cgi->Vars},
  {
    'field0-0-0' => 'short_desc',
    'field1-0-0' => 'short_desc',
    'type0-0-0'  => 'substring',
    'type1-0-0'  => 'substring',
    'value0-0-0' => 'batman',
    'value1-0-0' => 'robin',
  },
  "ALL search checks out"
);

$cgi = Bugzilla::CGI->fake_new();
quicksearch("ALL+ summary:batman AND summary:robin");
is(
  {$cgi->Vars},
  {
    'field0-0-0' => 'short_desc',
    'field1-0-0' => 'short_desc',
    'type0-0-0'  => 'substring',
    'type1-0-0'  => 'substring',
    'value0-0-0' => 'batman',
    'value1-0-0' => 'robin',
    'limit'      => 0,
  },
  "ALL+ search checks out"
);

$cgi = Bugzilla::CGI->fake_new();
quicksearch("FIXED summary:batman AND summary:robin");
{
  my %vars = $cgi->Vars;
  # the order here is random so we need to sort it.
  $vars{bug_status} = [sort @{$vars{bug_status}}];
  is(
    \%vars,
    {
      'bug_status' => ['RESOLVED', 'VERIFIED'],
      'resolution' => 'FIXED',
      'field0-0-0' => 'short_desc',
      'field1-0-0' => 'short_desc',
      'type0-0-0'  => 'substring',
      'type1-0-0'  => 'substring',
      'value0-0-0' => 'batman',
      'value1-0-0' => 'robin',
    },
    "FIXED search checks out"
  );
}

done_testing;
