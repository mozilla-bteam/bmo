#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Test::More;

# Load Bugzilla::Extension to install the INC_HOOK that maps
# Bugzilla::Extension::NAME::* to extensions/NAME/lib/*.
use_ok('Bugzilla::Extension');

# The INC_HOOK maps Bugzilla::Extension::InvalidBugHelper::* to
# extensions/InvalidBugHelper/lib/*.
use_ok('Bugzilla::Extension::InvalidBugHelper::WebService');
use_ok('Bugzilla::Extension::InvalidBugHelper::Config');

# Verify rest_resources returns the expected REST route.
my $resources = Bugzilla::Extension::InvalidBugHelper::WebService->rest_resources;
ok(ref $resources eq 'ARRAY', 'rest_resources returns an arrayref');
ok(scalar(@$resources) == 2, 'rest_resources has two elements (pattern + handler)');

my ($pattern, $handlers) = @$resources;
ok(ref $pattern eq 'Regexp', 'first element is a regex');
ok(exists $handlers->{POST}, 'handler defines a POST method');
ok($handlers->{POST}{method} eq 'close_as_invalid',
  'POST handler maps to close_as_invalid');

# Verify the route regex matches valid bug IDs and rejects invalid ones.
ok('/invalid_bug_helper/close/123' =~ $pattern, 'route matches numeric bug id');
ok('/invalid_bug_helper/close/0' =~ $pattern,   'route matches bug id 0');
ok('/invalid_bug_helper/close/abc' !~ $pattern,  'route rejects non-numeric id');
ok('/invalid_bug_helper/close/' !~ $pattern,     'route rejects missing id');

# Verify the params sub extracts bug_id from the capture group.
my $params_sub = $handlers->{POST}{params};
is(ref $params_sub, 'CODE', 'params is a code ref');
is_deeply($params_sub->(42), {bug_id => 42}, 'params sub extracts bug_id');

# Verify PUBLIC_METHODS includes close_as_invalid.
my @public = Bugzilla::Extension::InvalidBugHelper::WebService->PUBLIC_METHODS;
ok(grep({ $_ eq 'close_as_invalid' } @public),
  'close_as_invalid is in PUBLIC_METHODS');

# Verify Config returns the expected params.
my @params = Bugzilla::Extension::InvalidBugHelper::Config->get_param_list;
my %param_names = map { $_->{name} => 1 } @params;
ok($param_names{invalidbughelper_warning_text}, 'warning_text param defined');

done_testing();
