# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::BugGraph;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Graph::D3;
use List::Util qw(none);
use Mojo::Util qw(dumper);
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

  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $user         = $self->bugzilla->login;
  my $bug_id       = $self->param('id');
  my $type         = $self->param('type') || 'json_tree';
  my $relationship = $self->param('relationship');
  my $depth        = $self->param('depth') || 3;

  if ($bug_id !~ /^\d+$/) {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'bug_id'});
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

  if (none { $type eq $_ }
    qw(text json_tree bug_tree hierarchical_edge_bundling force_directed_graph))
  {
    ThrowCodeError('param_invalid',
      {function => 'bug/<id>/graph', param => 'type'});
  }

  my ($table, $fields, $source, $sink);
  if ($relationship) {
    my %relationships = (
      dependencies => ['dependson,blocked', 'blocked,dependson'],
      duplicates   => ['dupe,dupe_of',      'dupe_of,dupe']
    );
    ($table, $fields) = split /:/, $relationship;
    if ( none { $table eq $_ } keys %relationships
      || none { $fields eq $_ } @{$relationships{$table}})
    {
      ThrowCodeError('param_invalid',
        {function => 'bug/<id>/graph', param => 'relationship'});
    }
    ($table, $source, $sink) = ($table, split /,/, $fields // '');
  }

  my $result;
  try {
    Bugzilla->switch_to_shadow_db();
    my $report = Bugzilla::Report::Graph->new(
      dbh    => Bugzilla->dbh,
      bug_id => $bug_id,
      maybe
        table => $table,
      maybe
        source => $source,
      maybe
        sink => $sink,
      maybe depth => $depth,
    );

    # $report->prune_graph(sub { $user->visible_bugs($_[0]) });

    if ($type eq 'text') {
      $result = {text => $report->graph};
    }
    elsif ($type eq 'json_tree') {
      my $tree = $report->tree;
      $result = {tree => $tree};
    }
    elsif ($type eq 'bug_tree') {
      my $bugs = Bugzilla::Bug->new_from_list([$report->graph->vertices]);
      foreach my $bug (@$bugs) {
        $report->graph->set_vertex_attributes($bug->id, $self->_bug_to_hash($bug));
      }
      $result = {tree => $report->tree};
    }
    elsif ($type eq 'force_directed_graph' || $type eq 'hierarchical_edge_bundling')
    {
      $result = Graph::D3->new(graph => $report->graph)->$type;
    }
  }
  catch {
    FATAL($_);
    $result = {exception => 'Internal Error', request_id => $self->req->request_id};
  };

  return $self->render(json => $result);
}

sub _bug_to_hash {
  my ($self, $bug) = @_;
  return {
    summary => $bug->short_desc,
    keyword => [map { $_->name } @{$bug->keyword_objects}],
  };
}

1;
