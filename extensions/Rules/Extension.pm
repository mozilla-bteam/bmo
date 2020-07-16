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
use Bugzilla::Util qw(datetime_from);

use Bugzilla::Extension::Rules::Activity;
use Bugzilla::Extension::Rules::Rule;

our $VERSION = '0.01';

sub app_startup {
  my ($self, $args) = @_;
  my $routes = $args->{app}->routes;
  return Bugzilla::Extension::Rules::Activity->setup_routes($routes);
}

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

  return if (!$rules_enabled || !$rules_toml);

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

  if ($user->in_group('canconfirm', $bug->{'product_id'})) {

    # Canconfirm is really "cantriage"; users with canconfirm can also mark
    # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
    if ( $field eq 'bug_status'
      && is_open_state($old_value)
      && !is_open_state($new_value))
    {
      push @$priv_results, PRIVILEGES_REQUIRED_NONE;
    }
    elsif (
      $field eq 'resolution'
      && ( $new_value eq 'DUPLICATE'
        || $new_value eq 'WORKSFORME'
        || $new_value eq 'INCOMPLETE'
        || ($old_value eq '' && $new_value eq '1'))
      )
    {
      push @$priv_results, PRIVILEGES_REQUIRED_NONE;
    }
    elsif ($field eq 'dup_id') {
      push @$priv_results, PRIVILEGES_REQUIRED_NONE;
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

  return;
}

################
# Installation #
################

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  my $schema = $args->{schema};

  $schema->{'rules_activity'} = {
    FIELDS => [
      id  => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      change_when => {TYPE => 'DATETIME', NOTNULL => 1},
      rules       => {TYPE => 'LONGTEXT', NOTNULL => 1},
    ],
    INDEXES => [rules_activity_change_when_idx => ['change_when'],],
  };

  return;
}

__PACKAGE__->NAME;
