#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use lib qw(../../.. ../../../lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::WebService::Constants;

BEGIN {
  if (!Bugzilla->feature('rest') || !Bugzilla->feature('jsonrpc')) {
    ThrowUserError('feature_disabled', {feature => 'rest'});
  }
}

# Set request_cache bzapi value to true in order to enable the
# BzAPI extension functionality
Bugzilla->request_cache->{bzapi} = 1;

# Strip trailing slash before attempting match
# otherwise native REST will complain
my $path_info = Bugzilla->cgi->path_info;
if ($path_info =~ s'/$'') {

  # Remove first slash as cgi->path_info expects it to
  # not be there when setting a new path.
  Bugzilla->cgi->path_info(substr($path_info, 1));
}

use Bugzilla::WebService::Server::REST;
Bugzilla->usage_mode(USAGE_MODE_REST);
local @INC = (bz_locations()->{extensionsdir}, @INC);
my $server = new Bugzilla::WebService::Server::REST;
$server->version('1.1');
$server->handle();
