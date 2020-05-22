# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Config;

use 5.10.1;
use strict;
use warnings;

use Data::Dumper;
use TOML qw(from_toml);
use Try::Tiny;

use Bugzilla::Config::Common;
use Bugzilla::Logging;

our $sortkey = 1300;

sub get_param_list {
  my ($class) = @_;

  my @params = (
    {name => 'change_field_rules_enabled', type => 'b', default => 0},
    {
      name    => 'change_field_rules',
      type    => 'l',
      default => '',
      checker => sub {
        my ($toml) = @_;

        # Must be valid YAML
        try {
          my ($data, $err) = from_toml($toml);
          die $err if $err;
          return '';
        }
        catch {
          return "Must be valid TOML: $_";
        };
      }
    }
  );

  return @params;
}

1;
