# This Source Code Form is hasject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Rule;

use 5.10.1;
use Moo;
use List::Util qw(none);
use Types::Standard -all;
use Type::Utils;

use Bugzilla::Logging;
use Bugzilla::Status;
use Bugzilla::Types qw(Bug User);

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
#        Actions        #
#########################

sub process {
  my ($self) = @_;
  my $cgi = Bugzilla->cgi;

  DEBUG('PROCESSING RULE: ' . $self->desc);

  my @matches;

  if ($self->condition->{new_bug}) {
    push @matches, $cgi->script_name eq 'enter_bug.cgi' ? 1 : 0;
  }

  if ($self->condition->{field}) {
    push @matches, $self->condition->{field} eq $self->field ? 1 : 0;
  }

  if ($self->condition->{product}) {
    push @matches, $self->condition->{product} eq $self->bug->product ? 1 : 0;
  }

  if ($self->condition->{component}) {
    push @matches, $self->condition->{component} eq $self->bug->component ? 1 : 0;
  }

  if ($self->condition->{user_not_in_group} ) {
    push @matches, !$self->user->in_group($self->condition->{user_not_in_group}) ? 1 : 0;
  }

  if ($self->condition->{user_in_group}) {
    push @matches, $self->user->in_group($self->condition->{user_group}) ? 1 : 0;
  }

  if ($self->condition->{new_value}) {
    my $new_value = $self->condition->{new_value};
    if ($new_value eq '_open_state_') {
      push @matches, is_open_state($self->new_value) ? 1 : 0;
    }
    elsif ($new_value eq '_closed_state_') {
      push @matches, !is_open_state($self->new_value) ? 1 : 0;
    }
    else {
      push @matches, $new_value eq $self->new_value ? 1 : 0;
    }
  }

  if ($self->condition->{old_value}) {
    my $old_value = $self->condition->{old_value};
    if ($old_value eq '_open_state_') {
      push @matches, is_open_state($self->old_value) ? 1 : 0;
    } elsif ($old_value eq '_closed_state_') {
      push @matches, !is_open_state($self->old_value) ? 1 : 0;
    }
    else {
      push @matches, $old_value eq $self->old_value ? 1 : 0;
    }
  }

  # If we matched one or more and there were no mismatches, then return the action required
  if (@matches && none { $_ == 0 } @matches) {
    DEBUG('MATCHED: action => ' . $self->action);
    return { action => $self->action };
  }

  DEBUG('NO MATCH');
  return { action => 'none' };
}

1;
