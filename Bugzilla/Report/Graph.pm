# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::Graph;
use 5.10.1;
use Moo;

use Bugzilla::Types qw(DB);
use Graph::Directed;
use Graph::Traversal::DFS;
use Type::Utils qw(class_type);
use Types::Standard qw(Int Str ArrayRef Maybe);
use Set::Object qw(set);
use PerlX::Maybe;

has 'dbh'    => (is => 'ro',   isa => DB, required => 1);
has 'bug_id' => (is => 'ro',   isa => Int, required => 1);
has 'table'  => (is => 'ro',   isa => Str, default => 'dependencies');
has 'depth'  => (is => 'ro',   isa => Int, default => 3);
has 'source' => (is => 'ro',   isa => Str, default => 'dependson');
has 'sink'   => (is => 'ro',   isa => Str, default => 'blocked');
has 'limit'  => (is => 'ro',   isa => Maybe[Int], default => 10_000);

has 'paths'  => (is => 'lazy', isa => ArrayRef [ArrayRef]);

sub _build_paths {
  my ($self) = @_;

  return $self->dbh->selectall_arrayref($self->query, undef, $self->bug_id);
}

has 'graph' => (is => 'lazy', isa => class_type({class => 'Graph'}));

sub _build_graph {
  my ($self) = @_;
  my $paths = $self->paths;
  my $graph = Graph::Directed->new;

  foreach my $path (@$paths) {
    pop @$path until defined $path->[-1];
    $graph->add_path(@$path);
  }

  return $graph;
}

has 'query'  => (is => 'lazy', isa => Str);

sub _build_query {
  my ($self) = @_;
  my $table   = $self->table;
  my $alias   = substr($table, 0, 1);
  my $depth   = $self->depth;
  my $source  = $self->source;
  my $sink    = $self->sink;
  my $columns = join(", ", map {"$alias$_.$source"} 1 .. $depth);
  my $select  = "SELECT DISTINCT $columns";
  my $from    = "FROM $table AS ${alias}1";
  my $where   = "WHERE ${alias}1.$source = ?";
  my $limit   = defined($self->limit) ? "LIMIT " . $self->limit : "";
  my $joins   = join(
    "\n",
    map {
      my $d1 = $alias . $_;
      my $d2 = $alias . ($_ + 1);
      "LEFT JOIN $table AS $d2 ON $d1.$source = $d2.$sink",
    } 1 .. ($depth - 1)
  );

  return join("\n", $select, $from, $joins, $where, $limit);
}

sub prune_graph {
  my ($self, $filter) = @_;
  my $graph_vertices    = set($self->graph->vertices);
  my $filtered_vertices = set(@{$filter->($graph_vertices)});
  my $pruned_vertices   = $graph_vertices - $filtered_vertices;
  $self->graph->delete_vertices($pruned_vertices->members);

  my $reachable_vertices = set($self->bug_id, $self->graph->all_reachable($self->bug_id));
  my $unreachable_vertices = $filtered_vertices - $reachable_vertices;
  $self->graph->delete_vertices($unreachable_vertices->members);

  return $pruned_vertices + $unreachable_vertices;
}

sub tree {
  my ($self) = @_;
  my $g = $self->graph;
  my %nodes  = map { $_ => { maybe bug => $g->get_vertex_attributes($_) } } $g->vertices;
  my $search = Graph::Traversal::DFS->new(
    $g,
    start     => $self->bug_id,
    tree_edge => sub {
      my ($u, $v) = @_;
      $nodes{$u}{$v} = $nodes{$v};
    }
  );
  $search->dfs;

  return $nodes{$self->bug_id} || {};
}


1;
