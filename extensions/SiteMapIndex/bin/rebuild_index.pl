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

use lib qw(. lib local/lib/perl5);

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Constants;
use Bugzilla::Extension::SiteMapIndex::Util qw(generate_sitemap);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

generate_sitemap();
