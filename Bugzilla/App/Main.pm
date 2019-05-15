# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Main;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Logging;
use Bugzilla::Error;
use Try::Tiny;
use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;

  $r->any('/')->to('Main#root');

  $r->get('/testagent.cgi')->to('Main#testagent');

  $r->add_type('hex32' => qr/[[:xdigit:]]{32}/);
  $r->post('/announcement/hide/<checksum:hex32>')->to('Main#announcement_hide');

  $r->get('/attachment/<attachment_id:num>')->to('Main#access_raw_attachment');

  my $attachment_host_regex = Bugzilla->localconfig->attachment_host_regex;
  if ($attachment_host_regex) {
    $r->get('/attachment/<attachment_id:num>/raw')->name('view_raw_attachment')
      ->over(host => $attachment_host_regex)
      ->to('Main#view_raw_attachment',
      attachment_host_regex => $attachment_host_regex);
  }

  # $r->post('/bug/<bug_id:int>/attachment')->to('Main#attachment_create');
}

sub root {
  my ($c) = @_;
  $c->res->headers->cache_control('public, max-age=3600, immutable');
  $c->render(handler => 'bugzilla');
}

sub testagent {
  my ($self) = @_;
  $self->render(text => "OK Mojolicious");
}

sub announcement_hide {
  my ($self) = @_;
  my $checksum = $self->param('checksum');
  if ($checksum && $checksum =~ /^[[:xdigit:]]{32}$/) {
    $self->session->{announcement_checksum} = $checksum;
  }
  $self->render(json => {});
}


sub _raw_attachment_url {
  my ($self, $attachment) = @_;
  my $bug_id = $attachment->bug_id;
  my $base   = Bugzilla->localconfig->{attachment_base};
  $base =~ s/%bugid%/$bug_id/g;
  my $host = Mojo::URL->new($base)->host;

  return $self->url_for('view_raw_attachment', attachment_id => $attachment->id)
    ->to_abs->host($host);
}

sub access_raw_attachment {
  my ($self)        = @_;
  my $user          = $self->bugzilla->login(LOGIN_OPTIONAL);
  my $attachment_id = $self->stash->{attachment_id};
  my $attachment    = Bugzilla::Attachment->new($attachment_id);

  if ($attachment) {
    if ($attachment->is_public) {
      $self->redirect_to($self->_raw_attachment_url($attachment));
    }
  }
  else {
    $self->reply->not_found;
  }
}


sub view_raw_attachment {
  my ($self) = @_;

  my $attachment_id = $self->stash->{attachment_id};
  my $attachment    = Bugzilla::Attachment->new($attachment_id);
  if ($attachment) {
    $self->_send_attachment($attachment);
  }
  else {
    $self->reply->not_found;
  }
}

sub _send_redirect {
  my ($self, $user, $attachment) = @_;
  my $url            = $self->req->url->to_abs;
  my $iss            = $url->host;
  my $attachment_url = Bugzilla->localconfig->{attachment_base};

  my $claims = {
    iss        => $iss,
    aud        => sub => $user->id,
    attachment => $self->stash->{attachment_id},
  };
  my $t = $self->bugzilla->jwt(
    not_before => time,
    set_iat    => 1,
    expires    => time + 60 * 10,
    claims     => $claims,
  );

  return $t->encode;
}

sub _send_attachment {
  my ($self, $attachment) = @_;
  $self->render(data => $attachment->data);
  $self->res->headers->content_type($attachment->contenttype);
  $self->res->headers->content_length($attachment->datasize);
}

# sub create_attachment {
#   my ($self) = @_;
#   my $v = $self->validation;
#   $v->csrf_protect;
#   $v->required('bugid')->num;
#   $v->optional('ispatch')->equal_to('1');
#   $v->optional('isprivate')->equal_to('1');
# }

1;
