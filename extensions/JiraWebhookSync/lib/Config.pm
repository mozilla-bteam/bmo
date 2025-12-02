# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::JiraWebhookSync::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use JSON::MaybeXS qw(decode_json encode_json);

our $sortkey = 1300;

sub get_param_list {
  my ($class) = @_;

  my @params = (
    {name => 'jira_webhook_sync_hostname', type => 't', default => ''},
    {
      name    => 'jira_webhook_sync_user',
      type    => 't',
      default => '',
    },
    {
      name    => 'jira_webhook_sync_config',
      type    => 'l',
      default => '{}',
      checker => \&check_config,
    },
    {
      name    => 'jira_webhook_sync_project_keys',
      type    => 'l',
      default => '[]',
      checker => \&check_project_keys,
    },
  );

  return @params;
}

sub check_config {
  my $config = shift;
  my $val    = eval { decode_json($config) };
  return 'failed to parse JSON' unless defined $val;
  return 'value is not HASH'    unless ref $val && ref $val eq 'HASH';
  return '';
}

sub check_project_keys {
  my $config = shift;
  my $val    = eval { decode_json($config) };
  return 'failed to parse JSON' unless defined $val;
  return 'value is not ARRAY'   unless ref $val && ref $val eq 'ARRAY';
  return '';
}

1;
