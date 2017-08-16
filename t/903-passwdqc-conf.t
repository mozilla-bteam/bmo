#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use autodie;

use Test::More 1.302;
use ok 'Bugzilla::Config::Auth';

ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("undef, 24, 11, 8, 7")) == 0, "default value is valid");
ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("underf, 24, 11, 8, 7")) != 0, "underf is not valid");
is(Bugzilla::Config::Auth::_check_passwdqc_min("undef, 24, 25, 8, 7"), "Int2 is larger than Int1 (24)",  "25 can't come after 24");
ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("")) != 0, "empty string is invalid");
ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("24")) != 0, "24 is invalid");
ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("-24")) != 0, "-24 is invalid");
ok(length(Bugzilla::Config::Auth::_check_passwdqc_min("10, 10, 10, 10, 0")) != 0, "10, 10, 10, 10, 0 is invalid");

done_testing;
