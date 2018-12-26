# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Indexer;

use 5.10.1;
use Moo;
use List::MoreUtils qw(natatime);
use Storable qw(dclone);
use Scalar::Util qw(looks_like_number);
use Time::HiRes;
use namespace::clean;

with 'Bugzilla::Elastic::Role::HasClient';

has 'shadow_dbh' => (is => 'lazy');

has 'debug_sql' => (is => 'ro', default => 0,);

has 'progress_bar' => (is => 'ro', predicate => 'has_progress_bar',);


sub _create_index {
  my ($self, $class) = @_;
  my $indices    = $self->client->indices;
  my $index_name = $class->ES_INDEX;

  unless ($indices->exists(index => $index_name)) {
    $indices->create(
      index => $index_name,
      body  => {settings => $class->ES_SETTINGS},
    );
  }
}

sub _bulk_helper {
  my ($self, $class) = @_;

  return $self->client->bulk_helper(
    index => $class->ES_INDEX,
    type  => $class->ES_TYPE,
  );
}

sub _find_largest {
  my ($self, $class, $field) = @_;

  my $result = $self->client->search(
    index => $class->ES_INDEX,
    type  => $class->ES_TYPE,
    body  => {aggs => {$field => {extended_stats => {field => $field}}}, size => 0}
  );

  my $max = $result->{aggregations}{$field}{max};
  if (not defined $max) {
    return 0;
  }
  elsif (looks_like_number($max)) {
    return $max;
  }
  else {
    die "largest value for '$field' is not a number: $max";
  }
}

sub _find_largest_mtime {
  my ($self, $class) = @_;

  return $self->_find_largest($class, 'es_mtime');
}

sub _find_largest_id {
  my ($self, $class) = @_;

  return $self->_find_largest($class, $class->ID_FIELD);
}

sub _put_mapping {
  my ($self, $class) = @_;

  my %body = (properties => scalar $class->ES_PROPERTIES);
  if ($class->does('Bugzilla::Elastic::Role::ChildObject')) {
    $body{_parent} = {type => $class->ES_PARENT_TYPE};
  }

  $self->client->indices->put_mapping(
    index => $class->ES_INDEX,
    type  => $class->ES_TYPE,
    body  => \%body,
  );
}

sub _debug_sql {
  my ($self, $sql, $params) = @_;
  if ($self->debug_sql) {
    my ($out, @args) = ($sql, $params ? (@$params) : ());
    $out =~ s/^\n//gs;
    $out =~ s/^\s{8}//gm;
    $out =~ s/\?/Bugzilla->dbh->quote(shift @args)/ge;
    warn $out, "\n";
  }

  return ($sql, $params);
}

sub bulk_load {
  my ($self, $class) = @_;

  $self->_create_index($class);

  my $bulk        = $self->_bulk_helper($class);
  my $last_mtime  = $self->_find_largest_mtime($class);
  my $last_id     = $self->_find_largest_id($class);
  my $new_ids     = $self->_select_all_ids($class, $last_id);
  my $updated_ids = $self->_select_updated_ids($class, $last_mtime);

  $self->_put_mapping($class);
  $self->_bulk_load_ids($bulk, $class, $new_ids)     if @$new_ids;
  $self->_bulk_load_ids($bulk, $class, $updated_ids) if @$updated_ids;

  return {new => scalar @$new_ids, updated => scalar @$updated_ids,};
}

sub _select_all_ids {
  my ($self, $class, $last_id) = @_;

  my $dbh = Bugzilla->dbh;
  my ($sql, $params) = $self->_debug_sql($class->ES_SELECT_ALL_SQL($last_id));
  return $dbh->selectcol_arrayref($sql, undef, @$params);
}

sub _select_updated_ids {
  my ($self, $class, $last_mtime) = @_;

  my $dbh = Bugzilla->dbh;
  my ($updated_sql, $updated_params)
    = $self->_debug_sql($class->ES_SELECT_UPDATED_SQL($last_mtime));
  return $dbh->selectcol_arrayref($updated_sql, undef, @$updated_params);
}

sub bulk_load_ids {
  my ($self, $class, $ids) = @_;

  $self->_create_index($class);
  $self->_put_mapping($class);
  $self->_bulk_load_ids($self->_bulk_helper($class), $class, $ids);
}

sub _bulk_load_ids {
  my ($self, $bulk, $class, $all_ids) = @_;

  my $iter = natatime $class->ES_OBJECTS_AT_ONCE, @$all_ids;
  my $mtime = $self->_current_mtime;
  my $progress_bar;
  my $next_update;

  if ($self->has_progress_bar) {
    my $name = (split(/::/, $class))[-1];
    $progress_bar
      = $self->progress_bar->new({
      name => $name, count => scalar @$all_ids, ETA => 'linear'
      });
    $progress_bar->message(
      sprintf "loading %d $class objects, %d at a time",
      scalar @$all_ids,
      $class->ES_OBJECTS_AT_ONCE
    );
    $next_update = $progress_bar->update(0);
    $progress_bar->max_update_rate(1);
  }

  my $total = 0;
  my $start = time;
  while (my @ids = $iter->()) {
    if ($progress_bar) {
      $total += @ids;
      if ($total >= $next_update) {
        $next_update = $progress_bar->update($total);
        my $duration = time - $start || 1;
      }
    }

    my $objects = $class->new_from_list(\@ids);
    foreach my $object (@$objects) {
      my %doc
        = (id => $object->es_id, source => scalar $object->es_document($mtime),);

      if ($class->does('Bugzilla::Elastic::Role::ChildObject')) {
        $doc{parent} = $object->es_parent_id;
      }

      $bulk->index(\%doc);
    }
    Bugzilla->_cleanup();
  }

  $bulk->flush;
}

sub _build_shadow_dbh { Bugzilla->switch_to_shadow_db }

sub _current_mtime {
  my ($self) = @_;
  my ($mtime)
    = $self->shadow_dbh->selectrow_array("SELECT UNIX_TIMESTAMP(NOW())");
  return $mtime;
}

1;
