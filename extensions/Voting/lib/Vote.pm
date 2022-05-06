# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Voting::Vote;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;

use Scalar::Util qw(looks_like_number);

################################
####     Initialization     ####
################################

use constant DB_TABLE   => 'votes';
use constant LIST_ORDER => 'bug_id';
use constant ID_FIELD   => 'id';

use constant DB_COLUMNS => qw(
  id
  who
  bug_id
  vote_count
);

use constant UPDATE_COLUMNS => qw(
  vote_count
);

use constant VALIDATORS => {vote_count => \&_check_vote_count};

################################
####     Overrides          ####
################################

# We override the parent audit_log so we can store the bug id
# value instead of the vote table id. Also is we are creating a
# new vote table entry, then we record it as a vote_count change
# from 0 to the new count or vice versa.
sub audit_log {
  my ($self, $changes) = @_;
  my $new_changes = $changes;

  if ($changes eq AUDIT_CREATE || $changes eq AUDIT_REMOVE) {
    return if $self->vote_count == 0; # Do not record if changing from 0 to 0
    my @added_removed = $changes eq AUDIT_CREATE ? (0, $self->vote_count) : ($self->vote_count, 0);
    $new_changes = {vote_count => \@added_removed};
  }

  local $self->{id} = $self->bug_id;

  $self->SUPER::audit_log($new_changes);
}

################################
####     Validators         ####
################################

sub _check_vote_count {
  my ($invocant, $count) = @_;
  if ($count !~ /^[0-9]+$/) {
    ThrowCodeError('voting_count_invalid', {count => $count});
  }
  return $count;
}

###############################
####     Methods           ####
###############################

sub set_vote_count { $_[0]->set('vote_count', $_[1]); }

###############################
####     Accessors         ####
###############################

sub id         { return $_[0]->{'id'}; }
sub who        { return $_[0]->{'who'}; }
sub bug_id     { return $_[0]->{'bug_id'}; }
sub vote_count { return $_[0]->{'vote_count'}; }

1;
