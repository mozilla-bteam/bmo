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
  my $relationship  = $self->param('relationship') || 'dependencies';
  my $depth         = $self->param('depth')        || 3;
  my $ids_only      = $self->param('ids_only')      ? 1 : 0;
  my $show_resolved = $self->param('show_resolved') ? 1 : 0;

  if ($bug_id !~ /^\d+$/) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'bug_id'});
  }

  if ($depth !~ /^\d+$/ || ($depth > 9 || $depth < 1)) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'depth'});
  }

  my %relationships = (
    dependencies => ['dependson,blocked',      'blocked,dependson'],
    duplicates   => ['dupe,dupe_of',           'dupe_of,dupe'],
    regressions  => ['regresses,regressed_by', 'regressed_by,regresses'],
  );

  if (none { $relationship eq $_ } keys %relationships) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph ', param => 'relationship'});
  }

  my $result = {};
  try {
    foreach my $fields (@{$relationships{$relationship}}) {
      Bugzilla->switch_to_shadow_db();

      my ($source, $sink) = split /,/, $fields;

      my $report = Bugzilla::Report::Graph->new(
        bug_id => $bug_id,
        table  => $relationship,
        source => $source,
        sink   => $sink,
        depth  => $depth,
      );

      # Remove any secure bugs that user cannot see
      $report->prune_graph(sub { $user->visible_bugs($_[0]) });

      # If we do not want resolved bugs (default) then filter those
      # by passing in reference to the subroutine for filtering out
      # resolved bugs
      if (!$show_resolved) {
        $report->prune_graph(sub { $self->_prune_resolved($_[0]) });
      }

      if (!$ids_only) {
        my $bugs = Bugzilla::Bug->new_from_list([$report->graph->vertices]);
        foreach my $bug (@$bugs) {
          $report->graph->set_vertex_attributes($bug->id, $bug->to_hash);
        }
      }

      $result->{$source} = $report->tree;
    }
  }
  catch {
    FATAL($_);
    $result = {exception => 'Internal Error', request_id => $self->req->request_id};
  };

  return $self->render(json => $result);
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
