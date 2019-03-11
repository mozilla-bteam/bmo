# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::MyDashboard::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService Bugzilla::WebService::Bug);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural template_var datetime_from);
use Bugzilla::WebService::Util qw(validate);

use Bugzilla::Extension::MyDashboard::Queries
  qw(QUERY_DEFS query_bugs query_flags);
use Bugzilla::Extension::MyDashboard::BugInterest;

use constant READ_ONLY => qw(
  run_bug_query
  run_flag_query
);

use constant PUBLIC_METHODS => qw(
  bug_interest_unmark
  run_bug_query
  run_flag_query
  run_last_changes
);

sub run_last_changes {
  my ($self, $params) = @_;

  my $dbh  = Bugzilla->dbh;
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  my $last_comment_sql = "
        SELECT comment_id
            FROM longdescs
            WHERE bug_id = ? AND bug_when > ?";
  if (!$user->is_insider) {
    $last_comment_sql .= " AND isprivate = 0";
  }
  $last_comment_sql .= " LIMIT 1";
  my $last_comment_sth = $dbh->prepare($last_comment_sql);

  my $last_changes = {};
  my $activity
    = $self->history({
    ids => [$params->{bug_id}], new_since => $params->{changeddate_api}
    });
  if (@{$activity->{bugs}[0]{history}}) {
    my $change_set = $activity->{bugs}[0]{history}[0];
    $last_changes->{activity} = $change_set->{changes};
    foreach my $change (@{$last_changes->{activity}}) {
      $change->{field_desc} = template_var('field_descs')->{$change->{field_name}}
        || $change->{field_name};
    }
    $last_changes->{email} = $change_set->{who};
    my $datetime = datetime_from($change_set->{when});
    $datetime->set_time_zone($user->timezone);
    $last_changes->{when} = $datetime->strftime('%Y-%m-%d %T %Z');
  }
  my $last_comment_id
    = $dbh->selectrow_array($last_comment_sth, undef, $params->{bug_id},
    $params->{changeddate_api});
  if ($last_comment_id) {
    my $comments = $self->comments({comment_ids => [$last_comment_id]});
    my $comment = $comments->{comments}{$last_comment_id};
    $last_changes->{comment} = $comment->{text};
    $last_changes->{email} = $comment->{creator} if !$last_changes->{email};
    my $datetime = datetime_from($comment->{creation_time});
    $datetime->set_time_zone($user->timezone);
    $last_changes->{when} = $datetime->strftime('%Y-%m-%d %T %Z');
  }

  return {results => [{last_changes => $last_changes}]};
}

sub run_bug_query {
  my ($self, $params) = @_;
  my $dbh  = Bugzilla->dbh;
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  defined $params->{query}
    || ThrowCodeError('param_required',
    {function => 'MyDashboard.run_bug_query', param => 'query'});

  my $result;
  foreach my $qdef (QUERY_DEFS) {
    next if $qdef->{name} ne $params->{query};
    my ($bugs, $query_string) = query_bugs($qdef);

    # Add last changes to each bug
    foreach my $b (@$bugs) {

      # Set the data type properly for webservice clients
      # for non-string values.
      $b->{bug_id} = $self->type('int', $b->{bug_id});
    }

    $query_string =~ s/^POSTDATA=&//;
    $qdef->{bugs}   = $bugs;
    $qdef->{buffer} = $query_string;
    $result         = $qdef;
    last;
  }

  return {result => $result};
}

sub run_flag_query {
  my ($self, $params) = @_;
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  my $type = $params->{type};
  $type
    || ThrowCodeError('param_required',
    {function => 'MyDashboard.run_flag_query', param => 'type'});

  my $results = query_flags($type);

  # Set the data type properly for webservice clients
  # for non-string values.
  foreach my $flag (@$results) {
    $flag->{id}        = $self->type('int',     $flag->{id});
    $flag->{attach_id} = $self->type('int',     $flag->{attach_id});
    $flag->{bug_id}    = $self->type('int',     $flag->{bug_id});
    $flag->{is_patch}  = $self->type('boolean', $flag->{is_patch});
  }

  return {result => {$type => $results}};
}

sub bug_interest_unmark {
  my ($self, $params) = @_;
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  ThrowCodeError('param_required',
    {function => 'MyDashboard.bug_interest_unmark', param => 'bug_ids'})
    unless $params->{bug_ids};

  my @bug_ids
    = ref($params->{bug_ids}) ? @{$params->{bug_ids}} : ($params->{bug_ids});

  Bugzilla->dbh->bz_start_transaction();
  foreach my $bug_id (@bug_ids) {
    Bugzilla::Extension::MyDashboard::BugInterest->unmark($user->id, $bug_id);
  }
  Bugzilla->dbh->bz_commit_transaction();
}

sub rest_resources {
  return [qr{^/bug_interest_unmark$}, {PUT => {method => 'bug_interest_unmark'}}];
}

1;

__END__

=head1 NAME

Bugzilla::Extension::MyDashboard::Webservice - The MyDashboard WebServices API

=head1 DESCRIPTION

This module contains API methods that are useful to user's of bugzilla.mozilla.org.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.
