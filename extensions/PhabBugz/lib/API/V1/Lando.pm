# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::API::V1::Lando;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use JSON::Validator::Joi 'joi';
use Mojo::JSON qw(true false);

use Bugzilla::Constants;
use Bugzilla::Group;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;

our %api_field_names = reverse %{Bugzilla::Bug::FIELD_MAP()};
$api_field_names{'bug_group'} = 'groups';

sub setup_routes {
  my ($class, $r) = @_;
  $r->put('/lando/uplift')->to('PhabBugz::API::V1::Lando#uplift');
}

sub uplift {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  # Must be lando automation user to access this endpoint
  ($user->login eq LANDO_AUTOMATION_USER)
    || return $self->user_error('login_required');

  # Upgrade Lando user permissions to make changes to any bug
  $user->{groups}       = [Bugzilla::Group->get_all];
  $user->{bless_groups} = [Bugzilla::Group->get_all];

  my $params = $self->req->json;
  $params = Bugzilla::Bug::map_fields($params);

  my $ids = delete $params->{ids};
  defined $ids || ThrowCodeError('param_required', {param => 'ids'});

  my @bugs = map { Bugzilla::Bug->check($_) } @$ids;

  # Strictly prohibit the lando user from changing any fields
  # other than whiteboard and status flags
  foreach my $field (keys %{$params}) {
    if ($field ne 'status_whiteboard' && $field !~ /^cf_status_firefox/) {
      delete $params->{$field};
    }
  }

  # Update each bug
  foreach my $bug (@bugs) {
    $bug->set_all($params);
  }

  my %all_changes;

  my $dbh = Bugzilla->dbh;
  $dbh->bz_start_transaction();
  foreach my $bug (@bugs) {
    $all_changes{$bug->id} = $bug->update();
  }
  $dbh->bz_commit_transaction();

  foreach my $bug (@bugs) {
    $bug->send_changes($all_changes{$bug->id});
  }

  my @result;
  foreach my $bug (@bugs) {
    my %hash = (id => $bug->id, last_change_time => $bug->delta_ts, changes => {},);
    my %changes = %{$all_changes{$bug->id}};
    foreach my $field (keys %changes) {
      my $change    = $changes{$field};
      my $api_field = $api_field_names{$field} || $field;
      $change->[0] = '' if !defined $change->[0];
      $change->[1] = '' if !defined $change->[1];
      $hash{changes}->{$api_field} = {
        removed => $change->[0],
        added   => $change->[1],
      };
    }
    push @result, \%hash;
  }

  $self->render(json => {bugs => \@result});
}

1;
