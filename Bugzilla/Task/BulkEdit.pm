# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Task::BulkEdit;
use 5.10.1;
use Moo;

use Bugzilla::Error;
use DateTime::Duration;
use List::Util qw(any);
use Try::Tiny;
use Type::Utils qw(duck_type);
use Types::Standard -types;

with 'Bugzilla::Task';

has 'ids' => (is => 'ro', isa => ArrayRef [Int], required => 1);
has 'set_all' => (is => 'ro', isa => HashRef, required => 1);
has 'ids_with_ts' => (is => 'lazy', isa => ArrayRef [Tuple [Int, Str]]);

sub subject {
  my ($self) = @_;
  my @ids = @{$self->ids};

  if (@ids > 100) {
    return "Bulk Edit " . scalar(@ids) . " bugs";
  }
  else {
    return "Bulk Edit " . join(", ", @ids);
  }
}

sub _build_estimated_duration {
  my ($self) = @_;

  return DateTime::Duration->new(seconds => 0 + @{$self->ids});
}

sub prepare {
  my ($self) = @_;

  # pickup timestamps
  $self->ids_with_ts;
}

sub _build_ids_with_ts {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;

  return [] if @{$self->ids} == 0;
  return $dbh->selectall_arrayref(
    "SELECT bug_id, delta_ts FROM bugs WHERE @{[$dbh->sql_in('bug_id', $self->ids)]}"
  );
}

sub run {
  my ($self) = @_;

  return {async_bulk_edit => 1, all_sent_changes => [map { $self->edit_bug(@$_) } @{$self->ids_with_ts}]};
}

sub edit_bug {
  my ($self, $bug_id, $delta_ts) = @_;
  my $result;
  try {
    my $bug = Bugzilla::Bug->check($bug_id);
    ThrowUserError('bulk_edit_stale', {bug => $bug, expected_delta_ts => $delta_ts})
      unless $bug->delta_ts eq $delta_ts;
    ThrowUserError('product_edit_denied', {product => $bug->product})
      unless $self->user->can_edit_product($bug->product_obj->id);

    my $set_all_fields = $self->set_all;

    # Don't blindly ask to remove unchecked groups available in the UI.
    # A group can be already unchecked, and the user didn't try to remove it.
    # In this case, we don't want remove_group() to complain.
    my @remove_groups;
    my @unchecked_groups = @{$set_all_fields->{groups}{remove} // []};

    foreach my $group (@{$bug->groups_in}) {
      push(@remove_groups, $group->name)
        if any { $_ eq $group->name } @unchecked_groups;
    }

    local $set_all_fields->{groups}->{remove} = \@remove_groups;
    $bug->set_all($set_all_fields);
    my $changes = $bug->update();
    $result = $bug->send_changes($changes);
  }
  catch {
    $result = { bug_id => $bug_id, error => $_ };
  }
  finally {
    Bugzilla::Bug->CLEANUP();
  };

  return $result;
}

1;
