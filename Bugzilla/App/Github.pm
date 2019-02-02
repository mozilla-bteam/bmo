# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Github;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Constants;
use Bugzilla::Logging;
use Mojolicious::Validator;
use Try::Tiny;

sub setup_routes {
  my ($selflass, $r) = @_;
  $r->get('/github/configure')->to('Github#configure')->name('github_configure');
  $r->post('/github/generate')->to('Github#generate')->name('github_generate');
  $r->post('/github/webhook/*jwt')->to('Github#webhook')->name('github_webhook');
}

sub configure {
  my ($self) = @_;
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) or return;
  $self->render();
}

sub generate {
  my ($self) = @_;
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) or return;
  my $v    = $self->validation;
  $v->csrf_protect;
  _required_options($v);

  return $self->render('github/configure') if $v->has_error;

  $self->stash->{jwt} = Bugzilla->jwt(
    set_iat => 1,
    claims  => {
      bugzilla_url  => Bugzilla->localconfig->{urlbase},
      bugzilla_user => $user->id,
      auto_close    => $v->param('auto_close'),
      pull_request => $v->param('pull_request'),
    }
  );

  $self->render();
}

sub webhook {
  my ($self) = @_;
  try {
    my $event   = $self->req->headers->header('X-GitHub-Event') or die "Missing X-GitHub-Event";
    my $claims  = Bugzilla->jwt->decode($self->param('jwt'));
    my $v = $self->_validation_of_claims($claims);
    die Dumper($v) if $v->has_error;
    my $user = Bugzilla::User->check({id => $v->param('bugzilla_user') });
    my $guard = Bugzilla->set_user($user, scope_guard => 1);
    if ($event eq 'pull_request') {
      $self->_webhook_pull_request($v);
    }
    elsif ($event eq 'push') {
      $self->_webhook_push($v);
    }
    $self->render(json => {});
  }
  catch {
    ERROR("GitHub webhook error: $_");
    my $request_id = $self->req->request_id;
    $self->res->code(500);
    $self->render(json => { error => "Internal error (request id $request_id)"});
  };
}

sub _webhook_pull_request {
  my ($self, $v) = @_;
  return if $v->param('pull_request') eq 'do_nothing';
  my $pr = $self->req->json('/pull_request');
  my $title    = $pr->{title};
  my $body     = $pr->{body};
  my $html_url = $pr->{html_url};
  my $state    = $pr->{state};
  my $number   = $pr->{number};

  my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

  # TODO, for now it's just always bug 1.
  my $bug = Bugzilla::Bug->new(1);

  my $attachment = Bugzilla::Attachment->create({
    bug         => $bug,
    creation_ts => $timestamp,
    data        => $html_url,
    description => $title,
    filename    => "github-pr-$number",
    ispatch     => 0,
    isprivate   => 0,
    mimetype    => 'text/x-github-pull-request',
  });

  # Insert a comment about the new attachment into the database.
  $bug->add_comment(
    $body // '**no comment**',
    {
      type        => CMT_ATTACHMENT_CREATED,
      extra_data  => $attachment->id,
      is_markdown => (Bugzilla->params->{use_markdown} ? 1 : 0)
    }
  );
  $bug->update($timestamp);
}


sub _validation_of_claims {
  my ($self, $claims) = @_;
  my $validator = Mojolicious::Validator->new;
  my $v = $validator->validation;
  $v->input($claims);
  $v->required('bugzilla_url')->in(Bugzilla->localconfig->{urlbase});
  $v->required('bugzilla_user')->num;
  _required_options($v);
  return $v;
}

sub _required_options {
  my ($v) = @_;
  $v->required('auto_close')->in('default', 'leave_open');
  $v->required('pull_request')->in('do_nothing', 'attach_to_bug');
}

1;
