# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::Graph;
use 5.10.1;
use Moo;

use Graph::Directed;
use Graph::Traversal::BFS;
use PerlX::Maybe 'maybe';
use Type::Utils     qw(class_type);
use Types::Standard qw(Bool Enum Int Str ArrayRef Object);
use Set::Object     qw(set);

use Bugzilla;
use Bugzilla::Logging;
use Bugzilla::Types qw(DB);

our $valid_tables = [qw(dependencies duplicates regressions)];
our $valid_fields = [qw(blocked dependson dupe dupe_of regresses regressed_by)];

has bug_id => (is => 'ro', isa => Int, required => 1);
has table =>
  (is => 'ro', isa => Enum $valid_tables, default => 'dependencies',);
has depth  => (is => 'ro', isa => Int, default => 3);
has source => (is => 'ro', isa => Enum $valid_fields, default => 'dependson',);
has sink   => (is => 'ro', isa => Enum $valid_fields, default => 'blocked',);
has limit  => (is => 'ro', isa => Int, default => 10_000);
has paths  => (is => 'lazy', isa => ArrayRef [ArrayRef]);
has graph  => (is => 'lazy', isa => class_type({class => 'Graph'}));
has query  => (is => 'lazy', isa => Str);

# Run the query that will list of the paths from the parent bug
# down to the last child in the tree
sub _build_paths {
  my ($self) = @_;
  return Bugzilla->dbh->selectall_arrayref($self->query, undef, $self->bug_id);
}

# Builds a new directed graph
sub _build_graph {
  my ($self) = @_;
  my $paths  = $self->paths;
  my $graph  = Graph::Directed->new;

  foreach my $path (@$paths) {
    pop @$path until defined $path->[-2];
    $graph->add_path(@$path);
  }

  return $graph;
}

sub _build_query {
  my ($self) = @_;
  my $table  = $self->table;
  my $alias  = substr $table, 0, 1;
  my $depth  = $self->depth;
  my $source = $self->source;
  my $sink   = $self->sink;
  my $limit  = $self->limit;

  # WITH RECURSIVE is available in MySQL 8.x and newer as
  # well as recent versions of PostgreSQL and SQLite.
  my $query = "WITH RECURSIVE RelationshipTree AS (
    SELECT t.$source, t.$sink, 1 AS depth FROM $table t WHERE t.$source = ?
    UNION ALL
    SELECT t.$source, t.$sink, rt.depth + 1 AS depth FROM $table t
      JOIN RelationshipTree rt ON t.$source = rt.$sink WHERE rt.depth <= $depth LIMIT $limit)
    SELECT rt.$source, rt.$sink FROM RelationshipTree rt";

  return $query;
}

# Using a callback filter being passed in, remove any unwanted vertices
# in the graph such as secure bugs if the user cannot see them. Then
# remove any unreachable vertices as well.
sub prune_graph {
  my ($self, $filter) = @_;

  my $all_vertices      = set($self->graph->vertices);
  my $filtered_vertices = set(@{$filter->($all_vertices)});
  my $pruned_vertices   = $all_vertices - $filtered_vertices;
  $self->graph->delete_vertices($pruned_vertices->members);

  # Finally remove any vertices that are now unreachable
  my $reachable_vertices
    = set($self->bug_id, $self->graph->all_reachable($self->bug_id));
  my $unreachable_vertices = $filtered_vertices - $reachable_vertices;
  $self->graph->delete_vertices($unreachable_vertices->members);

  return $pruned_vertices + $unreachable_vertices;
}

# Generates the final tree stucture based on the directed graph
sub tree {
  my ($self) = @_;
  my $graph = $self->graph;

  my %nodes = map { $_ => {maybe bug => $graph->get_vertex_attributes($_)} }
    $graph->vertices;

  my $search = Graph::Traversal::BFS->new(
    $graph,
    start     => $self->bug_id,
    tree_edge => sub {
      my ($u, $v) = @_;
      $nodes{$u}{$v} = $nodes{$v};
    }
  );
  $search->bfs;

  return $nodes{$self->bug_id} || {};
}

# Remove any secure bugs that user cannot see
sub prune_secure {
  my ($self, $bugs, $user) = @_;
  $user ||= Bugzilla->user;

  $self->prune_graph(sub {
    $user->visible_bugs($_[0]);
  });

  return $self;
}

# This method takes a set of bugs and using a single SQL statement,
# removes any bugs from the list which have a non-empty resolution (unresolved)
sub prune_resolved {
  my ($self, $bugs) = @_;

  $self->prune_graph(sub {
    my $bugs = $_[0];

    return $bugs if !$bugs->size;

    my $placeholders = join ',', split //, '?' x $bugs->size;
    my $query
      = "SELECT bug_id FROM bugs WHERE (resolution IS NULL OR resolution = '') AND bug_id IN ($placeholders)";
    my $filtered_bugs
      = Bugzilla->dbh->selectcol_arrayref($query, undef, $bugs->elements);

    return $filtered_bugs;
  });

  return $self;
}

1;
