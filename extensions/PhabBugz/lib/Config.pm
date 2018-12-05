# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 1300;

sub get_param_list {
  my ($class) = @_;

  my @params = (
    {name => 'phabricator_enabled', type => 'b', default => 0},
    {
      name    => 'phabricator_base_uri',
      type    => 't',
      default => '',
      checker => \&check_urlbase
    },
    {name => 'phabricator_api_key', type => 't', default => '',},
    {
      name    => 'phabricator_auth_callback_url',
      type    => 't',
      default => '',
      checker => sub {
        my ($url) = (@_);
        return 'must be an HTTP/HTTPS absolute URL' unless $url =~ m{^https?://};
        return '';
      }
    },
    {
      name    => 'phabricator_app_id',
      type    => 't',
      default => '',
      checker => sub {
        my ($app_id) = (@_);
        return 'must be a hex number' unless $app_id =~ /^[[:xdigit:]]+$/;
        return '';
      }
    }
  );

  return @params;
}

1;
