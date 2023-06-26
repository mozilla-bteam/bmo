# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::API::V1::PhabBugz;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Logging;
use Bugzilla::Util qw(trim);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;

use List::Util qw(uniq);

our %api_field_names = reverse %{Bugzilla::Bug::FIELD_MAP()};
$api_field_names{'bug_group'} = 'groups';

sub setup_routes {
  my ($class, $r) = @_;

  # Lando automation related endpoints
  $r->get('/lando/uplift')->to('PhabBugz::API::V1::PhabBugz#get_bugs');
  $r->get('/lando/uplift/:id')->to('PhabBugz::API::V1::PhabBugz#get_bugs');
  $r->put('/lando/uplift')->to('PhabBugz::API::V1::PhabBugz#update_bugs');

  # Pulsebot automation related endpoints
  $r->get('/pulsebot/bug')->to('PhabBugz::API::V1::PhabBugz#get_bugs');
  $r->get('/pulsebot/bug/:id')->to('PhabBugz::API::V1::PhabBugz#get_bugs');
  $r->get('/pulsebot/bug/:id/comment')
    ->to('PhabBugz::API::V1::PhabBugz#get_comments');
  $r->post('/pulsebot/bug/:id/comment')
    ->to('PhabBugz::API::V1::PhabBugz#add_comment');
  $r->put('/pulsebot/bug')->to('PhabBugz::API::V1::PhabBugz#update_bugs');
}

sub get_bugs {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  WARN('PHABBUGZ get_bugs');

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  WARN('PHABBUGZ get_bugs user: ' . $user->id);

  # Must be permitted automation user to access this endpoint
  if ( $user->login ne LANDO_AUTOMATION_USER
    && $user->login ne PULSEBOT_AUTOMATION_USER)
  {
    return $self->user_error('login_required');
  }

  # Upgrade user permissions to make changes to any bug
  $user->{groups}       = [Bugzilla::Group->get_all];
  $user->{bless_groups} = [Bugzilla::Group->get_all];

  my @ids = split /,/, $self->param('id');
  @ids || ThrowCodeError('param_required', {param => 'id'});

  my @results;
  foreach my $id (@ids) {
    my $bug = Bugzilla::Bug->check($id);

    my $result = {
      id         => $bug->id,
      keywords   => [map { $_->name } @{$bug->keyword_objects}],
      whiteboard => $bug->status_whiteboard,
    };

    if ($user->login eq LANDO_AUTOMATION_USER) {
      my $flags = Bugzilla::Extension::TrackingFlags::Flag->match(
        {bug_id => $bug->id, is_active => 1});
      foreach my $flag (@{$flags}) {
        my $flag_name = $flag->name;
        $result->{$flag_name} = $bug->$flag_name;
      }
    }

    if ($user->login eq PULSEBOT_AUTOMATION_USER) {
      $result->{status} = $bug->bug_status;
    }

    push @results, $result;
  }

  $self->render(json => {bugs => \@results});
}

sub get_comments {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  WARN('PHABBUGZ get_comments');

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  WARN('PHABBUGZ get_comments user: ' . $user->id);

  # Must be permitted automation user to access this endpoint
  if ($user->login ne PULSEBOT_AUTOMATION_USER) {
    return $self->user_error('login_required');
  }

  # Upgrade user permissions to retrieve comment for any bug
  $user->{groups}       = [Bugzilla::Group->get_all];
  $user->{bless_groups} = [Bugzilla::Group->get_all];

  $self->param('id') || ThrowCodeError('param_required', {param => 'id'});

  my $bug = Bugzilla::Bug->check($self->param('id'));

  my $comments = $bug->comments({order => 'oldest_to_newest'});

  # Only return the comment text and the comment tags
  my @result;
  foreach my $comment (@$comments) {
    next if $comment->is_private;
    push @result, {
      id   => $comment->id,
      tags => $comment->tags,
      text => $comment->body_full
    };
  }

  $self->render(json => {bugs => {$bug->id => {comments => \@result}}});
}

sub add_comment {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  WARN('PHABBUGZ add_comment');

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  WARN('PHABBUGZ add_comment user: ' . $user->id);

  # Must be permitted automation user to access this endpoint
  if ($user->login ne PULSEBOT_AUTOMATION_USER) {
    return $self->user_error('login_required');
  }

  # Upgrade user permissions to add a comment to any bug
  $user->{groups}       = [Bugzilla::Group->get_all];
  $user->{bless_groups} = [Bugzilla::Group->get_all];

  $self->param('id') || ThrowCodeError('param_required', {param => 'id'});

  my $json_params = $self->req->json;

  my $comment = $json_params->{comment};
  (defined $comment && trim($comment) ne '')
    || ThrowCodeError('param_required', {param => 'comment'});

  my $bug = Bugzilla::Bug->check($self->param('id'));

  # Append comment
  $bug->add_comment($comment);

  # Allow setting of comment tags such as an uplift revision comment
  if ($json_params->{comment_tags}) {
    $bug->set_all({comment_tags => $json_params->{comment_tags}});
  }

  my $dbh = Bugzilla->dbh;
  $dbh->bz_start_transaction();

  $bug->update();

  my $new_comment_id = $dbh->bz_last_key('longdescs', 'comment_id');

  $dbh->bz_commit_transaction();

  # Send mail.
  Bugzilla::BugMail::Send($bug->bug_id, {changer => Bugzilla->user});

  $self->render(json => {id => $new_comment_id});
}

sub update_bugs {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  WARN('PHABBUGZ update_bugs');

  my $user = $self->bugzilla->login;
  $user->id || return $self->user_error('login_required');

  WARN('PHABBUGZ update_bugs user: ' . $user->id);

  # Must be permitted automation user to access this endpoint
  if ( $user->login ne LANDO_AUTOMATION_USER
    && $user->login ne PULSEBOT_AUTOMATION_USER)
  {
    return $self->user_error('login_required');
  }

  # Upgrade user permissions to make changes to any bug
  $user->{groups}       = [Bugzilla::Group->get_all];
  $user->{bless_groups} = [Bugzilla::Group->get_all];

  my $params = $self->req->json;
  $params = Bugzilla::Bug::map_fields($params);

  my $ids = delete $params->{ids};
  defined $ids || return $self->code_error('param_required', {param => 'ids'});

  my @bugs = map { Bugzilla::Bug->check($_) } @{$ids};

  my @allowed_fields;
  if ($user->login eq LANDO_AUTOMATION_USER) {
    @allowed_fields = LANDO_BUG_UPDATE_FIELDS;
  }
  if ($user->login eq PULSEBOT_AUTOMATION_USER) {
    @allowed_fields = PULSEBOT_BUG_UPDATE_FIELDS;
  }

  # Strictly prohibit the user from changing any fields
  # other than ones allowed for the user.
  my $allowed_params = {};
  foreach my $param (keys %{$params}) {
    foreach my $field (@allowed_fields) {
      # We handle custom fields differently by using a regexp match
      if (($param =~ /^cf_/ && $field =~ /^cf_/ && $param =~ /^$field/) || $param eq $field) {
        $allowed_params->{$param} = delete $params->{$param};
        last;
      }
    }
  }

  # If any additional parameters were passed then we will throw an error
  if (%{$params}) {
    return $self->code_error('too_many_params',
      {allowed_params => \@allowed_fields});
  }

  # Update each bug
  foreach my $bug (@bugs) {
    $bug->set_all($allowed_params);
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
      $hash{changes}->{$api_field}
        = {removed => $change->[0], added => $change->[1],};
    }
    push @result, \%hash;
  }

  $self->render(json => {bugs => \@result});
}

1;
