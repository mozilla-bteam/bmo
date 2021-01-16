# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Status qw(is_open_state);
use Bugzilla::Util qw(datetime_from);

our $VERSION = '0.1';

# Who can set custom flags (use full field names only, not regex's)
our $cf_setters
  = {'cf_colo_site' => ['infra', 'build'], 'cf_rank' => ['rank-setters'],};

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $priv_results = $args->{'priv_results'};
  my $user         = Bugzilla->user;

  if ($field =~ /^cf/ && !@$priv_results && $new_value ne '---') {

    # Cannot use the standard %cf_setter mapping as we want anyone
    # to be able to set ?, just not the other values.
    if ($field eq 'cf_cab_review') {
      if ( $new_value ne '1'
        && $new_value ne '?'
        && !$user->in_group('infra', $bug->product_id))
      {
        push @{$priv_results},
          {
          result => PRIVILEGES_REQUIRED_EMPOWERED,
          reason => 'Specific permissions are required to make this change',
          };
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
        push @{$priv_results},
          {
          result => PRIVILEGES_REQUIRED_EMPOWERED,
          reason => 'Specific permissions are required to make this change',
          };
      }
    }
  }
  elsif ($field eq 'resolution' && $new_value eq 'FIXED') {

    # You need at least canconfirm to mark a bug as FIXED
    if (!$user->in_group('canconfirm', $bug->{'product_id'})) {
      push @{$priv_results},
        {
        result => PRIVILEGES_REQUIRED_EMPOWERED,
        reason => 'You need "canconfirm" permissions to mark a bug as RESOLVED/FIXED',
        };
    }
  }
  elsif (($field eq 'bug_status' && $old_value eq 'VERIFIED')
    || ($field eq 'dup_id'     && $bug->status->name eq 'VERIFIED')
    || ($field eq 'resolution' && $bug->status->name eq 'VERIFIED'))
  {
    # You need at least editbugs to reopen a resolved/verified bug
    if (!$user->in_group('editbugs', $bug->{'product_id'})) {
      push @{$priv_results},
        {
        result => PRIVILEGES_REQUIRED_EMPOWERED,
        reason => 'You require "editbugs" permission to reopen a RESOLVED/VERIFIED bug',
        };
    }
  }
  elsif ($user->in_group('canconfirm', $bug->{'product_id'})) {

    # Canconfirm is really "cantriage"; users with canconfirm can also mark
    # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
    if ( $field eq 'bug_status'
      && is_open_state($old_value)
      && !is_open_state($new_value))
    {
      push @{$priv_results}, {result => PRIVILEGES_REQUIRED_NONE};
    }
    elsif (
      $field eq 'resolution'
      && ( $new_value eq 'DUPLICATE'
        || $new_value eq 'WORKSFORME'
        || $new_value eq 'INCOMPLETE'
        || ($old_value eq '' && $new_value eq '1'))
      )
    {
      push @{$priv_results}, {result => PRIVILEGES_REQUIRED_NONE};
    }
    elsif ($field eq 'dup_id') {
      push @{$priv_results}, {result => PRIVILEGES_REQUIRED_NONE};
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
        push @{$priv_results},
          {
          result => PRIVILEGES_REQUIRED_EMPOWERED,
          reason => 'Bugs closed as FIXED cannot be reopened after one year',
          };
      }
    }
  }
}

__PACKAGE__->NAME;
