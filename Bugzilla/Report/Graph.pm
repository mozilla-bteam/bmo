# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::Graph;
use 5.10.1;
use Moo;

use Types::Standard qw(Int Str);
use Bugzilla::Types qw(DB);
use Graph::Directed;
use Graph::Traversal::DFS;

has 'graph'   => (is => 'lazy');
has 'tree'    => (is => 'lazy');
has '_query'  => (is => 'lazy', isa => Str);
has 'dbh'     => (is => 'ro', isa => DB, required => 1);
has 'bug_id'  => (is => 'ro', isa => Int, required => 1);
has 'table'   => (is => 'ro', isa => Str, default => 'dependencies');
has 'depth'   => (is => 'ro', isa => Int, default => 3);
has 'source'  => (is => 'ro', isa => Str, default => 'dependson');
has 'sink'    => (is => 'ro', isa => Str, default => 'blocked');

sub _build_graph {
  my ($self) = @_;
  my $dbh   = $self->dbh;
  my $paths = $dbh->selectall_arrayref($self->_query, undef, $self->bug_id);
  my $graph  = Graph::Directed->new;

  foreach my $path (@$paths) {
    pop @$path until defined $path->[-1];
    $graph->add_path(@$path);
  }

  return $graph;
}

sub _build_tree {
  my ($self) = @_;
  my $g = $self->graph;
  my %nodes = map { $_ => {} } $g->vertices;
  my $search = Graph::Traversal::DFS->new($g, start => $self->bug_id, tree_edge => sub {
    my ($u, $v) = @_;
    $nodes{$u}{$v} = $nodes{$v};
  });
  $search->dfs;

  return $nodes{$self->bug_id};
}

sub _build__query {
  my ($self) = @_;
  my $table  = $self->table;
  my $prefix = substr($table, 0, 1);
  my $depth  = $self->depth;
  my $source = $self->source;
  my $sink   = $self->sink;

  my $select = 'DISTINCT ' . join(", ", map { "$prefix$_.$source" } 1 .. $depth);
  my $from = "FROM $table AS ${prefix}1";
  my $joins = join(
    "\n",
    map {
      my $d1 = $prefix . $_;
      my $d2 = $prefix . ($_ + 1);
      "LEFT JOIN $table AS $d2 ON $d1.$source = $d2.$sink",
    } 1 .. ($depth - 1)
  );
  my $where = "WHERE ${prefix}1.$source = ?";

  return "SELECT $select $from\n$joins\n$where";
}


1;
