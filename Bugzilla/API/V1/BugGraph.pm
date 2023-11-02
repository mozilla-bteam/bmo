# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::BugGraph;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use List::Util qw(any none);
use PerlX::Maybe;
use Try::Tiny;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Report::Graph;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/bug/:id/graph')->to('V1::BugGraph#graph');
}

sub graph {
  my ($self, $params) = @_;
  my $user = $self->bugzilla->login;

  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $bug_id        = $self->param('id');
  my $relationship  = $self->param('relationship');
  my $depth         = $self->param('depth');
  my $type          = $self->param('type') || 'bug_tree';
  my $show_resolved = $self->param('show_resolved') ? 1 : 0;

  if ($bug_id !~ /^\d+$/) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'bug_id'});
  }

  if (none { $type eq $_ } qw(bug_tree json_tree)) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'type'});
  }

  if (defined $depth) {
    if ($depth !~ /^\d+$/) {
      ThrowCodeError('param_invalid',
        {function => 'bug/<id>/graph', param => 'depth'});
    }

    if ($depth > 9 || $depth < 1) {
      ThrowCodeError('param_invalid',
        {function => 'bug/<id>/graph', param => 'depth'});
    }
  }

  my ($table, $fields, $source, $sink);
  if ($relationship) {
    my %relationships = (
      dependencies => ['dependson,blocked',      'blocked,dependson'],
      duplicates   => ['dupe,dupe_of',           'dupe_of,dupe'],
      regressions  => ['regresses,regressed_by', 'regressed_by,regresses'],
    );

    ($table, $fields) = split /:/, $relationship;

    my $relationship_valid = 1;
    if (none { $table eq $_ } keys %relationships) {
      $relationship_valid = 0;
    }
    if (none { $fields eq $_ } @{$relationships{$table}}) {
      $relationship_valid = 0;
    }

    if (!$relationship_valid) {
      ThrowCodeError('param_invalid',
        {function => 'bug/<id>/graph ', param => 'relationship'});
    }

    ($table, $source, $sink) = ($table, split /,/, $fields // '');
  }

  my $result;
  try {
    Bugzilla->switch_to_shadow_db();
    my $report = Bugzilla::Report::Graph->new(
      bug_id => $bug_id,
      maybe
        table => $table,
      maybe
        source => $source,
      maybe
        sink => $sink,
      maybe depth => $depth,
    );

    # Remove any secure bugs that user cannot see
    $report->prune_graph(sub { $user->visible_bugs($_[0]) });

    # If we do not want resolved bugs (default) then filter those
    # by passing in reference to the subroutine for filtering out
    # resolved bugs
    if (!$show_resolved) {
      $report->prune_graph(sub { $self->_prune_resolved($_[0]) });
    }

    if ($type ne 'json_tree') {
      my $bugs = Bugzilla::Bug->new_from_list([$report->graph->vertices]);
      foreach my $bug (@$bugs) {
        $report->graph->set_vertex_attributes($bug->id, $self->_bug_to_hash($bug));
      }
    }

    $result = {tree => $report->tree};
  }
  catch {
    FATAL($_);
    $result = {exception => 'Internal Error', request_id => $self->req->request_id};
  };

  return $self->render(json => $result);
}

# Adds extra data to the vertices of the graph.
sub _bug_to_hash {
  my ($self, $bug) = @_;
  return {
    summary    => $bug->short_desc,
    status     => $bug->bug_status,
    resolution => $bug->resolution,
    milestone  => $bug->target_milestone,
    assignee   => $bug->assigned_to->name,
  };
}

# This method takes a set of bugs and using a single SQL statement,
# removes any bugs from the list which have a non-empty resolution (unresolved)
sub _prune_resolved {
  my ($self, $bugs) = @_;
  my $dbh = Bugzilla->dbh;

  return $bugs if !$bugs->size;

  my $placeholders = join ',', split //, '?' x $bugs->size;
  my $query
    = "SELECT bug_id FROM bugs WHERE (resolution IS NULL OR resolution = '') AND bug_id IN ($placeholders)";
  my $filtered_bugs
    = Bugzilla->dbh->selectcol_arrayref($query, undef, $bugs->elements);

  return $filtered_bugs;
}

1;
