# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Pre::CommentClosedBugs;

use 5.10.1;
use Moo;

use Bugzilla::Constants;

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug        = $args->{'bug'};
  my $field      = $args->{'field'};
  my $new_value  = $args->{'new_value'};
  my $old_value  = $args->{'old_value'};
  my $canconfirm = $args->{'canconfirm'};
  my $user       = Bugzilla->user;


  # If this bug is closed and the current user has no role on the bug, then do
  # not allow commenting on a bug that is not open.
  if ( $field =~ /^longdesc/
    && $bug->id
    && !$bug->isopened
    && $new_value ne $old_value)
  {
    my $has_role
      = (  $canconfirm
        || $bug->reporter->id eq $user->id
        || $bug->assigned_to->id eq $user->id
        || ($bug->qa_contact && $bug->qa_contact->id eq $user->id)) ? 1 : 0;

    # If the current user has a needinfo flag requested of them,
    # then allow commenting
    foreach my $flag (@{$bug->flags}) {
      next if $flag->type->name ne 'needinfo';
      if ( $flag->status eq '?'
        && $flag->requestee
        && $flag->requestee->id == $user->id)
      {
        $has_role = 1;
      }
    }

    return {result => PRIVILEGES_REQUIRED_NONE} if $has_role;

    return {
      result => PRIVILEGES_REQUIRED_EMPOWERED,
      reason => 'You need permission to comment on this closed bug.',
    };
  }

  return undef;
}

1;
