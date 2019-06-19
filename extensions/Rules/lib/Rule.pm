# This Source Code Form is hasject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Rule;

use 5.10.1;
use Moo;

use Bugzilla::Logging;
use Bugzilla::Status;
use Bugzilla::Types qw(Bug User);

use Types::Standard -all;
use Type::Utils;

#########################
#    Initialization     #
#########################

has desc      => (is => 'ro', isa => Str);
has condition => (is => 'ro', isa => Dict);
has action    => (is => 'ro', isa => Str);
has bug       => (is => 'ro', isa => Bug);
has field     => (is => 'ro', isa => Str);
has new_value => (is => 'ro', isa => Maybe [Str | ArrayRef]);
has old_value => (is => 'ro', isa => Maybe [Str | ArrayRef]);
has user      => (is => 'ro', isa => User);

sub BUILDARGS {
  my ($class, $params) = @_;

  $params->{desc}      = $params->{rule}->{desc};
  $params->{condition} = $params->{rule}->{condition};
  $params->{action}    = $params->{rule}->{action};

  delete $params->{rule};

  return $params;
}

#########################
#       Utilities       #
#########################

sub allow {
  my ($self) = @_;

  DEBUG('Processing rule: ' . ($self->desc || 'No description'));

  my $matched = 0;

  if ($self->condition->{field}) {
    $matched = $self->condition->{field} eq $self->field ? 1 : 0;
  }

  if ($self->condition->{product}) {
    $matched = $self->condition->{product} eq $self->bug->product ? 1 : 0;
  }

  if ($self->condition->{component}) {
    $matched = $self->condition->{component} eq $self->bug->component ? 1 : 0;
  }

  if ($self->condition->{user_not_in_group} ) {
    $matched
      = !$self->user->in_group($self->condition->{user_not_in_group}) ? 1 : 0;
  }

  if ($self->condition->{user_in_group}) {
    $matched = $self->user->in_group($self->condition->{user_group}) ? 1 : 0;
  }

  if ($self->condition->{new_value}) {
    my $new_value = $self->condition->{new_value};
    if ($new_value eq '_open_state_') {
      $matched = is_open_state($self->new_value) ? 1 : 0;
    }
    elsif ($new_value eq '_closed_state_') {
      $matched = !is_open_state($self->new_value) ? 1 : 0;
    }
    else {
      $matched = $new_value eq $self->new_value ? 1 : 0;
    }
  }

  if ($self->condition->{old_value}) {
    my $old_value = $self->condition->{old_value};
    if ($old_value eq '_open_state_') {
      $matched = is_open_state($self->old_value) ? 1 : 0;
    } elsif ($old_value eq '_closed_state_') {
      $matched = !is_open_state($self->old_value) ? 1 : 0;
    }
    else {
      $matched = $old_value eq $self->old_value ? 1 : 0;
    }
  }

  if ($matched) {
    return ($self->action && $self->action eq 'deny') ? 0 : 1;
  }

  return 1;
}

#########################
#    Private Methods    #
#########################

1;
