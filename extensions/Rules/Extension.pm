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
use YAML;

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Status;

use Bugzilla::Extension::BMO::Data;
use Bugzilla::Extension::Rules::Rule;

our $VERSION = '0.01';

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{Rules} = 'Bugzilla::Extension::Rules::Config';
}

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $priv_results = $args->{'priv_results'};
  my $user         = Bugzilla->user;

  my $rules_enabled = Bugzilla->params->{change_field_rules_enabled};
  my $rules_yaml    = Bugzilla->params->{change_field_rules};

  return unless ($rules_enabled && $rules_yaml);

  my $rule_defs;
  try {
    $rule_defs = Load($rules_yaml);
  }
  catch {
    FATAL("Unable to load YAML: $_");
  };

  foreach my $rule_def (@{$rule_defs->{rules}}) {
    my $rule = Bugzilla::Extension::Rules::Rule->new({
      rule      => $rule_def,
      bug       => $bug,
      user      => $user,
      field     => $field,
      new_value => $new_value,
      old_value => $old_value,
    });
    DEBUG('PROCESSING RULE: ' . $rule->desc);
    if (!$rule->allow) {
      DEBUG('RULE: Not Allowed');
      push @{$priv_results}, PRIVILEGES_REQUIRED_EMPOWERED;
    }
  }

  # Old stuff to be migrated

  if ($field =~ /^cf/ && !@$priv_results && $new_value ne '---') {

    # Cannot use the standard %cf_setter mapping as we want anyone
    # to be able to set ?, just not the other values.
    if ($field eq 'cf_cab_review') {
      if ( $new_value ne '1'
        && $new_value ne '?'
        && !$user->in_group('infra', $bug->product_id))
      {
        push(@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
      }
    }

    # "other" custom field setters restrictions
    elsif (exists $cf_setters->{$field}) {
      my $in_group = 0;
      foreach my $group (@{$cf_setters->{$field}}) {
        if ($user->in_group($group, $bug->product_id)) {
          $in_group = 1;
          last;
        }
      }
      if (!$in_group) {
        push(@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
      }
    }
  }

  elsif ($user->in_group('canconfirm', $bug->{'product_id'})) {

    # Canconfirm is really "cantriage"; users with canconfirm can also mark
    # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
    if ( $field eq 'bug_status'
      && is_open_state($old_value)
      && !is_open_state($new_value))
    {
      push(@$priv_results, PRIVILEGES_REQUIRED_NONE);
    }
    elsif (
      $field eq 'resolution'
      && ( $new_value eq 'DUPLICATE'
        || $new_value eq 'WORKSFORME'
        || $new_value eq 'INCOMPLETE'
        || ($old_value eq '' && $new_value eq '1'))
      )
    {
      push(@$priv_results, PRIVILEGES_REQUIRED_NONE);
    }
    elsif ($field eq 'dup_id') {
      push(@$priv_results, PRIVILEGES_REQUIRED_NONE);
    }

  }

  elsif ($field eq 'bug_status') {

    # Disallow reopening of bugs which have been resolved for > 1 year
    if ( is_open_state($new_value)
      && !is_open_state($old_value)
      && $bug->resolution eq 'FIXED')
    {
      my $days_ago = DateTime->now(time_zone => Bugzilla->local_timezone);
      $days_ago->subtract(days => 365);
      my $last_closed = datetime_from($bug->last_closed_date);
      if ($last_closed lt $days_ago) {
        push(@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
      }
    }
  }
}

__PACKAGE__->NAME;
