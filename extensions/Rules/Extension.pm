# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::Extension);

use Try::Tiny;
use TOML qw(from_toml);

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Status;

use Bugzilla::Extension::BMO::Data;
use Bugzilla::Extension::Rules::Rule;

our $VERSION = '0.01';

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  return $modules->{Rules} = 'Bugzilla::Extension::Rules::Config';
}

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my ($bug, $field, $new_value, $old_value, $priv_results)
    = @$args{qw(bug field new_value old_value priv_results)};
  my $user          = Bugzilla->user;
  my $request_cache = Bugzilla->request_cache;

  my $rules_enabled = Bugzilla->params->{change_field_rules_enabled};
  my $rules_toml    = Bugzilla->params->{change_field_rules};

  if ($rules_enabled && $rules_toml) {
    DEBUG('CHECKING RULES');
    my $rule_defs;
    try {
      $rule_defs = $request_cache->{rule_defs} ||= from_toml($rules_toml);
    }
    catch {
      FATAL("Unable to load TOML: $_");
    };

    foreach my $rule_def (@{$rule_defs->{rule}}) {
      my $rule = Bugzilla::Extension::Rules::Rule->new({
        rule      => $rule_def,
        bug       => $bug,
        user      => $user,
        field     => $field,
        new_value => $new_value,
        old_value => $old_value,
      });

      $rule->debug_info();

      my $result = $rule->process();
      if ($result->{action} eq 'deny') {

        # Explicitly deny
        push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
      }
      elsif ($result->{action} eq 'allow') {

        # Explicitly allow
        push @{$priv_results}, PRIVILEGES_REQUIRED_NONE;
      }
    }

    return;
  }
}

__PACKAGE__->NAME;
