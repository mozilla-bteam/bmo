# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::OAuth2Client;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 1350;

sub get_param_list {
  my ($class) = @_;

  my @params = (
    {name => 'oauth2_client_enabled',       type => 'b', default => 0,},
    {name => 'oauth2_client_domain',        type => 't', default => '',},
    {name => 'oauth2_client_id',            type => 't', default => '',},
    {name => 'oauth2_client_secret',        type => 't', default => '',},
    {name => 'oauth2_client_token_url',     type => 't', default => '',},
    {name => 'oauth2_client_authorize_url', type => 't', default => '',},
    {name => 'oauth2_client_userinfo_url',  type => 't', default => '',},
    {name => 'oauth2_client_scopes',        type => 't', default => '',},
  );

  return @params;
}

1;
