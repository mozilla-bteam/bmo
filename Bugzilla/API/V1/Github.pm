# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Github;
use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Logging;
use Bugzilla::User;

use Digest::SHA qw(hmac_sha256_hex);
use Mojo::Util  qw(secure_compare);

# Stolen from pylib/mozautomation/mozautomation/commitparser.py from
# https://hg.mozilla.org/hgcustom/version-control-tools
use constant BUG_RE => qr/
  (
    (?:
      bug |
      b= |
      (?=\b\#?\d{5,}) |
      ^(?=\d)
    )
    (?:\s*\#?)(\d+)(?=\b)
  )/ix;

sub setup_routes {
  my ($class, $r) = @_;
  $r->post('/github/pull_request')->to('V1::Github#pull_request');
}

sub pull_request {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  # Return early if not a pull_request event
  my $event = $self->req->headers->header('X-GitHub-Event');
  return $self->render(json => {error => 'Not pull request'}, status => 400)
    if (!$event || $event ne 'pull_request');

  # Verify that signature is correct based on shared secret
  return $self->render(
    json   => {error => 'Payload signatures did not match'},
    status => 400
  ) if !$self->verify_signature;

  # Parse pull request title for bug ID
  my $payload = $self->req->json;
  if ( !$payload
    || !$payload->{pull_request}
    || !$payload->{pull_request}->{html_url}
    || !$payload->{pull_request}->{title})
  {
    return $self->render(json => {error => 'Invalid JSON data'}, status => 400);
  }

  my $html_url = $payload->{pull_request}->{html_url};
  my $title    = $payload->{pull_request}->{title};
  $title =~ BUG_RE;
  my $bug_id = $2;
  my $bug    = Bugzilla::Bug->new($bug_id);
  return $self->render(json => {error => 'Valid bug ID was not found'},
    status => 400)
    if !$bug;

  # Check if bug already has this pull request attached
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->content_type ne 'text/x-github-pull-request';
    if ($attachment->data eq $html_url) {
      return $self->render(
        json   => {error => 'Pull request already attached'},
        status => 400
      );
    }
  }

  # Create new attachment using pull request URL as attachment content
  my $auto_user = Bugzilla::User->check({name => 'automation@bmo.tld'});
  $auto_user->{groups}       = [Bugzilla::Group->get_all];
  $auto_user->{bless_groups} = [Bugzilla::Group->get_all];
  Bugzilla->set_user($auto_user);

  my $timestamp = Bugzilla->dbh->selectrow_array("SELECT NOW()");

  my $attachment = Bugzilla::Attachment->create({
    bug         => $bug,
    creation_ts => $timestamp,
    data        => $html_url,
    description => 'GitHub Pull Request',
    filename    => 'file_' . $bug->id . '.txt',
    ispatch     => 0,
    isprivate   => 0,
    mimetype    => 'text/x-github-pull-request',
  });

  # Insert a comment about the new attachment into the database.
  $bug->add_comment(
    '',
    {
      type        => CMT_ATTACHMENT_CREATED,
      extra_data  => $attachment->id,
      is_markdown => (Bugzilla->params->{use_markdown} ? 1 : 0)
    }
  );
  $bug->update($timestamp);

  # Return success
  return $self->render(json => {id => $attachment->id});
}

sub verify_signature {
  my ($self)             = @_;
  my $payload            = $self->req->body;
  my $secret             = Bugzilla->params->{github_pr_signature_secret};
  my $received_signature = $self->req->headers->header('X-Hub-Signature-256');
  my $expected_signature = 'sha256=' . hmac_sha256_hex($secret, $payload);
  return secure_compare($expected_signature, $received_signature) ? 1 : 0;
}

1;
