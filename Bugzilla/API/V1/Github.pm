# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Github;
use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::User;

use Digest::SHA qw(hmac_sha256_hex);
use Mojo::Util  qw(secure_compare);

sub setup_routes {
  my ($class, $r) = @_;
  $r->post('/github/pull_request')->to('V1::Github#pull_request');
}

sub pull_request {
  my ($self) = @_;
  my $template = Bugzilla->template;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  # Return early if linking is not allowed
  return $self->code_error('github_pr_linking_disabled')
    if !Bugzilla->params->{github_pr_linking_enabled};

  # Return early if not a pull_request or ping event
  my $event = $self->req->headers->header('X-GitHub-Event');
  if (!$event || ($event ne 'pull_request' && $event ne 'ping')) {
    return $self->code_error('github_pr_not_pull_request');
  }

  # Verify that signature is correct based on shared secret
  if (!$self->verify_signature) {
    return $self->code_error('github_pr_mismatch_signatures');
  }

  # If event is a ping and we passed the signature check
  # then return success
  if ($event eq 'ping') {
    return $self->render(json => {error => 0});
  }

  # Parse pull request title for bug ID
  my $payload = $self->req->json;
  if ( !$payload
    || !$payload->{action}
    || !$payload->{pull_request}
    || !$payload->{pull_request}->{html_url}
    || !$payload->{pull_request}->{title}
    || !$payload->{pull_request}->{number}
    || !$payload->{repository}->{full_name})
  {
    return $self->code_error('github_pr_invalid_json');
  }

  # We are only interested in new pull request events
  # and not changes to existing ones (non-fatal).
  my $message;
  if ($payload->{action} ne 'opened') {
    $template->process('global/code-error.html.tmpl',
      {error => 'github_pr_invalid_event'}, \$message)
      || die $template->error();
    return $self->render(json => {error => 1, message => $message});
  }

  my $html_url   = $payload->{pull_request}->{html_url};
  my $title      = $payload->{pull_request}->{title};
  my $pr_number  = $payload->{pull_request}->{number};
  my $repository = $payload->{repository}->{full_name};

  # Find bug ID in the title and see if bug exists and client
  # can see it (non-fatal).
  my ($bug_id) = $title =~ /\b[Bb]ug[ -](\d+)\b/;
  my $bug      = Bugzilla::Bug->new($bug_id);
  if ($bug->{error}) {
    $template->process('global/code-error.html.tmpl',
      {error => 'github_pr_bug_not_found'}, \$message)
      || die $template->error();
    return $self->render(json => {error => 1, message => $message});
  }

  # Check if bug already has this pull request attached (non-fatal)
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->contenttype ne 'text/x-github-pull-request';
    if ($attachment->data eq $html_url) {
      $template->process('global/code-error.html.tmpl',
        {error => 'github_pr_attachment_exists'}, \$message)
        || die $template->error();
      return $self->render(json => {error => 1, message => $message});
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
    description => "[$repository] $title (#$pr_number)",
    filename    => "github-$pr_number-url.txt",
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

  # Fixup attachments with same github pull request but on different bugs
  my %other_bugs;
  my $other_attachments = Bugzilla::Attachment->match({
    mimetype => 'text/x-github-pull-request',
    filename => "github-$pr_number-url.txt",
    WHERE    => {'bug_id != ? AND NOT isobsolete' => $bug->id}
  });
  foreach my $attachment (@$other_attachments) {
    # same pr number but different repo so skip it
    next if $attachment->data ne $html_url;

    $other_bugs{$attachment->bug_id}++;
    my $moved_comment
      = "GitHub pull request attachment was moved to bug "
      . $bug->id
      . ". Setting attachment "
      . $attachment->id
      . " to obsolete.";
    $attachment->set_is_obsolete(1);
    $attachment->bug->add_comment(
      $moved_comment,
      {
        type        => CMT_ATTACHMENT_UPDATED,
        extra_data  => $attachment->id,
        is_markdown => (Bugzilla->params->{use_markdown} ? 1 : 0)
      }
    );
    $attachment->bug->update($timestamp);
    $attachment->update($timestamp);
  }

  # Return new attachment id when successful
  return $self->render(json => {error => 0, id => $attachment->id});
}

sub verify_signature {
  my ($self)             = @_;
  my $payload            = $self->req->body;
  my $secret             = Bugzilla->params->{github_pr_signature_secret};
  my $received_signature = $self->req->headers->header('X-Hub-Signature-256');
  my $expected_signature = 'sha256=' . hmac_sha256_hex($payload, $secret);
  return secure_compare($expected_signature, $received_signature) ? 1 : 0;
}

1;
