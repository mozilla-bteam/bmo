# This Source Code Form is hasject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules::Rule;

use 5.10.1;
use Data::Dumper;
use Moo;
use List::Util qw(any);
use Types::Standard -all;
use Type::Utils;

use Bugzilla::Logging;
use Bugzilla::Status;
use Bugzilla::Types qw(Bug FakeBug User);

#########################
#    Initialization     #
#########################

# Rule definitions
has action    => (is => 'ro', isa => ArrayRef | Str);
has change    => (is => 'ro', isa => Maybe [Dict]);
has condition => (is => 'ro', isa => Maybe [Dict]);
has error     => (is => 'ro', isa => Maybe [Str]);
has filter    => (is => 'ro', isa => Maybe [Dict]);
has name      => (is => 'ro', isa => Str);

# Current attributes
has bug       => (is => 'ro', isa => Bug | FakeBug);
has user      => (is => 'ro', isa => User);
has field     => (is => 'ro', isa => Str);
has old_value => (is => 'ro', isa => Str);
has new_value => (is => 'ro', isa => Str);

sub BUILDARGS {
  my ($class, $params) = @_;

  $params->{action}    = $params->{rule}->{action};
  $params->{change}    = $params->{rule}->{change};
  $params->{condition} = $params->{rule}->{condition};
  $params->{error}     = $params->{rule}->{error};
  $params->{filter}    = $params->{rule}->{filter};
  $params->{name}      = $params->{rule}->{name};

  delete $params->{rule};

  return $params;
}

#########################
#        Actions        #
#########################

sub process {
  my ($self) = @_;
  my @matches;

  # Process filter first
  if ($self->filter) {
    if ($self->filter->{field} eq 'product') {
      push @matches, $self->filter->{value} eq $self->bug->product ? 1 : 0;
    }
    if ($self->filter->{field} eq 'component') {
      push @matches, $self->filter->{value} eq $self->bug->component ? 1 : 0;
    }
  }

  # Then process what is changing
  if ($self->change) {
    if ($self->change->{field}) {
      push @matches, $self->change->{field} eq $self->field ? 1 : 0;
    }
    if ($self->change->{old_value}) {
      push @matches, $self->change->{old_value} eq $self->old_value ? 1 : 0;
    }
    if ($self->change->{new_value}) {
      push @matches, $self->change->{new_value} eq $self->new_value ? 1 : 0;
    }
  }

  # Finally process the special conditions that need to be met
  if ($self->condition) {
    if ($self->condition->{not_user_group}) {
      push @matches,
        !$self->user->in_group($self->condition->{not_user_group}) ? 1 : 0;
    }
    if ($self->condition->{user_group}) {
      push @matches, $self->user->in_group($self->condition->{user_group}) ? 1 : 0;
    }
  }

  # If we have not fully matched by this point we ignore this rule
  if (any { $_ == 0 } @matches) {
    DEBUG('NO MATCH');
    return {action => 'none'};
  }
  else {
    my $result = {action => 'allow'};

    # Process actions since we matched
    my $action = ref $self->action ? $self->action : [$self->action];

    # cannot_create means we disallow this change for new bugs
    if (any { $_ eq 'cannot_create' } @{$action} && !$self->bug->id) {
      $result = {action => 'deny'};
    }

    # cannot_update means we disallow this change for any bug, even current
    if (any { $_ eq 'cannot_update' } @{$action}) {
      $result = {action => 'deny'};
    }

    DEBUG('MATCHED: ' . $result->{action});

    return $result;
  }

#   if ($self->condition->{new_value}) {
#     my $new_value = $self->condition->{new_value};
#     if ($new_value eq '_open_state_') {
#       push @matches, is_open_state($self->new_value) ? 1 : 0;
#     }
#     elsif ($new_value eq '_closed_state_') {
#       push @matches, !is_open_state($self->new_value) ? 1 : 0;
#     }
#     else {
#       push @matches, $new_value eq $self->new_value ? 1 : 0;
#     }
#   }

#   if ($self->condition->{old_value}) {
#     my $old_value = $self->condition->{old_value};
#     if ($old_value eq '_open_state_') {
#       push @matches, is_open_state($self->old_value) ? 1 : 0;
#     }
#     elsif ($old_value eq '_closed_state_') {
#       push @matches, !is_open_state($self->old_value) ? 1 : 0;
#     }
#     else {
#       push @matches, $old_value eq $self->old_value ? 1 : 0;
#     }
#   }
}

sub debug_info {
  my ($self) = @_;
  DEBUG('PROCESSING RULE: ' . $self->name);
  DEBUG('user: ' . $self->user->login);
  DEBUG('bug: ' . ($self->bug->id || 'None'));
  DEBUG('field: ' . $self->field);
  DEBUG('old_value: ' . $self->old_value);
  DEBUG('new_value: ' . $self->new_value);
  DEBUG('product: ' . $self->bug->product);
  DEBUG('component: ' . ($self->bug->component || 'None'));
  DEBUG(
    'action: ' . (ref $self->action ? join ',', @{$self->action} : $self->action));
}

1;
