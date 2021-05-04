# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Pre::CanConfirm;

use 5.10.1;
use Moo;

use Bugzilla::Constants;
use Bugzilla::Status qw(is_open_state);

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $priv_results = $args->{'priv_results'};
  my $canconfirm   = $args->{'canconfirm'};

  # Canconfirm is really "cantriage"; users with canconfirm can also mark
  # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
  if (
       $canconfirm
    && $field eq 'resolution'
    && ( $new_value eq 'DUPLICATE'
      || $new_value eq 'WORKSFORME'
      || $new_value eq 'INCOMPLETE'
      || ($old_value eq '' && $new_value eq '1'))
    )
  {
    return {result => PRIVILEGES_REQUIRED_NONE,};
  }

  if ($canconfirm && $field eq 'dup_id') {
    return {result => PRIVILEGES_REQUIRED_NONE,};
  }

  if ( $canconfirm
    && $field eq 'bug_status'
    && is_open_state($old_value)
    && !is_open_state($new_value))
  {
    return {result => PRIVILEGES_REQUIRED_NONE,};
  }

  # You need at least canconfirm to mark a bug as FIXED
  if (!$canconfirm && $field eq 'resolution' && $new_value eq 'FIXED') {
    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You need "canconfirm" permissions to mark a bug as fixed.',
    };
  }

  return undef;
}

1;
