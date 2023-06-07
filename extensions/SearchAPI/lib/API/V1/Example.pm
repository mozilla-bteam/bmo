# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::SearchAPI::API::V1::Example;

use Mojo::Base qw(Mojolicious::Controller);

use Bugzilla::Extension::SearchAPI::Util qw(named_params);

use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('search/bug_statuses')->to('SearchAPI::API::V1::Example#bug_statuses');
}

sub bug_statuses {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $value = $self->param('value');

  my $query = 'SELECT * FROM bug_status ';

  if ($value) {
    $query .= ' WHERE value = :value';
  }

  $query .= ' ORDER by sortkey';

  my ($updated_query, $values) = named_params($query, {value => $value});

  my $rows = Bugzilla->dbh->selectall_arrayref($updated_query, {'Slice' => {}}, @{$values});

  return $self->render(json => {result => $rows});
}

1;
