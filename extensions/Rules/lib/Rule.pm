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
  if (my $filter = $self->filter) {
    foreach my $item (qw(product component)) {
      if (exists $filter->{$item}) {
        push @matches, $filter->{$item} eq $self->bug->$item ? 1 : 0;
      }
    }
  }

  # Then process what is changing
  if (my $change = $self->change) {
    if ($change->{field}) {
      push @matches, $change->{field} eq $self->field ? 1 : 0;
    }

    foreach my $item (qw(new_value old_value not_new_value not_old_value)) {
      if (my $values = $change->{$item}) {
        $values = ref $values ? $values : [$values];
        foreach my $value (@{$values}) {
          if ($value eq '_open_state_') {
            push @matches, is_open_state($self->$item) ? 1 : 0;
          }
          elsif ($value eq '_closed_state_') {
            push @matches, !is_open_state($self->$item) ? 1 : 0;
          }
          else {
            if ($item =~ /^not_/) {
              my $not_item = $item;
              $not_item =~ s/^not_//;
              push @matches, $value ne $self->$not_item ? 1 : 0;
            }
            else {
              push @matches, $value eq $self->$item ? 1 : 0;
            }
          }
        }
      }
    }
  }

  # Finally process the special conditions that need to be met
  if (my $condition = $self->condition) {
    if ($condition->{not_user_group}) {
      my $values
        = ref $condition->{not_user_group}
        ? $condition->{not_user_group}
        : [$condition->{not_user_group}];
      my $in_group = 0;
      foreach my $value (@{$values}) {
        if ($self->user->in_group($value)) {
          $in_group = 1;
          last;
        }
      }
      push @matches, !$in_group ? 1 : 0;
    }
    foreach my $item (qw(bug_status)) {
      if (exists $condition->{$item}) {
        push @matches, $condition->{$item} eq $self->bug->$item ? 1 : 0;
      }
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
    if (any { $_ eq 'cannot_update' || $_ eq 'cannot_comment' } @{$action}) {
      $result = {action => 'deny'};
    }

    DEBUG('MATCHED: ' . $result->{action});

    return $result;
  }
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
