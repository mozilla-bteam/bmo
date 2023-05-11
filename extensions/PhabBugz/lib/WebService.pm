# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural);
use Bugzilla::WebService::Constants;
use Types::Standard qw(-types slurpy);
use Type::Params qw(compile);

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::Util qw(request);

use MIME::Base64 qw(decode_base64);
use Try::Tiny;

use constant READ_ONLY => qw(
  bug_revisions
  check_user_enter_bug_permission
  check_user_permission_for_bug
);

use constant PUBLIC_METHODS => qw(
  bug_revisions
  check_user_enter_bug_permission
  check_user_permission_for_bug
);

sub _check_phabricator {

  # Ensure PhabBugz is on
  ThrowUserError('phabricator_not_enabled')
    unless Bugzilla->params->{phabricator_enabled};
}

sub _validate_phab_user {
  my ($self, $user) = @_;

  $self->_check_phabricator();

  # Validate that the requesting user's email matches phab-bot
  ThrowUserError('phabricator_unauthorized_user')
    unless $user->login eq PHAB_AUTOMATION_USER;
}

sub check_user_permission_for_bug {
  my ($self, $params) = @_;

  my $user = Bugzilla->login(LOGIN_REQUIRED);

  $self->_validate_phab_user($user);

  # Validate that a bug id and user id are provided
  ThrowUserError('phabricator_invalid_request_params')
    unless ($params->{bug_id} && $params->{user_id});

  # Validate that the user exists
  my $target_user = Bugzilla::User->check({id => $params->{user_id}, cache => 1});

  # Send back an object which says { "result": 1|0 }
  return {result => $target_user->can_see_bug($params->{bug_id})};
}

sub check_user_enter_bug_permission {
  my ($self, $params) = @_;

  my $user = Bugzilla->login(LOGIN_REQUIRED);

  $self->_validate_phab_user($user);

  # Validate that a product name and user id are provided
  ThrowUserError('phabricator_invalid_request_params')
    unless ($params->{product} && $params->{user_id});

  # Validate that the user exists
  my $target_user = Bugzilla::User->check({id => $params->{user_id}, cache => 1});

  # Send back an object with the attribute "result" set to 1 if the user
  # can enter bugs into the given product, or 0 if not.
  return {result => $target_user->can_enter_product($params->{product}) ? 1 : 0};
}

sub bug_revisions {
  state $check = compile(Object, Dict [bug_id => Int]);
  my ($self, $params) = $check->(@_);

  $self->_check_phabricator();

  my $user = Bugzilla->login(LOGIN_REQUIRED);

  # Validate that a bug id and user id are provided
  ThrowUserError('phabricator_invalid_request_params') unless $params->{bug_id};

  # Validate that the user can see the bug itself
  my $bug = Bugzilla::Bug->check({id => $params->{bug_id}, cache => 1});

  my @revision_ids;
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->contenttype ne PHAB_CONTENT_TYPE;
    my ($revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
    next if !$revision_id;
    push @revision_ids, int $revision_id;
  }

  my $response = request(
    'differential.revision.search',
    {
      attachments => {
        'projects'        => 1,
        'reviewers'       => 1,
        'subscribers'     => 1,
        'reviewers-extra' => 1,
      },
      constraints => {ids => \@revision_ids,},
      order       => 'newest',
    }
  );

  state $SearchResult = Dict [
    result => Dict [

      # HashRef below could be better,
      # but ::Revision takes a lot of options.
      data => ArrayRef [HashRef],
      slurpy Any,
    ],
    slurpy Any,
  ];

  my $error = $SearchResult->validate($response);
  ThrowCodeError('phabricator_api_error', {reason => $error}) if defined $error;

  my $children_map = $self->_get_children_map($response);

  my $revision_status_map = {
    'abandoned'       => 'Abandoned',
    'accepted'        => 'Accepted',
    'changes-planned' => 'Changes Planned',
    'draft'           => 'Draft',
    'needs-review'    => 'Needs Review',
    'needs-revision'  => 'Needs Revision',
  };

  my $review_status_map = {
    'accepted'       => 'Accepted',
    'accepted-prior' => 'Accepted Prior Diff',
    'added'          => 'Review Requested',
    'blocking'       => 'Blocking Review',
    'rejected'       => 'Requested Changes',
    'resigned'       => 'Resigned'
  };

  my @revisions;
  foreach my $revision (@{$response->{result}{data}}) {

    # Skip if revision bug id was moved to a different bug
    next if $revision->{fields}->{'bugzilla.bug-id'} ne $bug->id;

    my $revision_obj  = Bugzilla::Extension::PhabBugz::Revision->new($revision);
    my $id = $revision_obj->id;
    my $revision_data = {
      id          => 'D' . $id,
      sortkey     => $id,
      status      => $revision_obj->status,
      long_status => $revision_status_map->{$revision_obj->status}
        || $revision_obj->status
    };

    my @reviews;
    foreach my $review (@{$revision_obj->reviews}) {
      push @reviews,
        {
        user        => $review->{user}->name,
        status      => $review->{status},
        long_status => $review_status_map->{$review->{status}} || $review->{status}
        };
    }
    $revision_data->{reviews} = \@reviews;

    if ($revision_obj->view_policy ne 'public') {
      $revision_data->{title}     = '(secured)';
      $revision_data->{call_sign} = '(secured)';
    }
    else {
      $revision_data->{title} = $revision_obj->title;
      $revision_data->{call_sign}
        = $revision_obj->repository ? $revision_obj->repository->call_sign : 'N/A';
    }

    $revision_data->{children} = [map { "D$_" } @{$children_map->{$id}}];

    push @revisions, $revision_data;
  }

  # sort by revision id
  @revisions = sort { $a->{sortkey} <=> $b->{sortkey} } @revisions;

  return {revisions => \@revisions};
}

sub _get_children_map {
  my ($self, $revisions_response) = @_;

  my @revision_phids;
  foreach my $revision (@{$revisions_response->{result}{data}}) {
    push @revision_phids, $revision->{phid};
  }

  my $edge_response = request(
    'edge.search',
    {
      sourcePHIDs => \@revision_phids,
      types       => ["revision.child"],
    }
  );

  my $rev_phid_to_id = {};
  my $children_map = {};
  foreach my $revision (@{$revisions_response->{result}{data}}) {
    my $id = $revision->{id};
    my $phid = $revision->{phid};
    $rev_phid_to_id->{$phid} = $id;
    $children_map->{$id} = [];
  }

  foreach my $edge (@{$edge_response->{result}{data}}) {
    if (!exists($rev_phid_to_id->{$edge->{sourcePHID}})) {
      next;
    }
    if (!exists($rev_phid_to_id->{$edge->{destinationPHID}})) {
      next;
    }

    my $from = $rev_phid_to_id->{$edge->{sourcePHID}};
    my $to = $rev_phid_to_id->{$edge->{destinationPHID}};

    if (!exists($children_map->{$from})) {
      next;
    }

    push @{$children_map->{$from}}, $to;
  }

  return $children_map;
}

sub user {
  state $check = compile(Object, Dict [user_id => Int]);
  my ($self, $params) = $check->(@_);

  $self->_check_phabricator();

  Bugzilla->login(LOGIN_REQUIRED);

  my $bmo_user_id = $params->{user_id};

  my $response = request(
    'bmoexternalaccount.search',
    {
      accountids => [$bmo_user_id],
    }
  );
  if (scalar(@{$response->{result}}) == 0) {
    return {};
  }

  my $phid = $response->{result}[0]{phid};

  $response = request(
    'user.query',
    {
      phids => [$phid],
    }
  );
  if (scalar(@{$response->{result}}) == 0) {
    return {};
  }

  my $user_name = $response->{result}[0]{userName};
  my $real_name = $response->{result}[0]{realName};

  my $base_url = Bugzilla->params->{phabricator_base_uri};
  $base_url =~ s{/$}{};
  my $user_url = "$base_url/p/$user_name/";
  my $revisions_url = "$base_url/differential/?responsiblePHIDs%5B0%5D=$phid&statuses%5B0%5D=open()&order=newest&bucket=action";

  return {
    user => {
      phid => $phid,
      userName => $user_name,
      realName => $real_name,
      userURL => $user_url,
      revisionsURL => $revisions_url,
    },
  };
}

sub rest_resources {
  return [
    # Bug permission checks
    qr{^/phabbugz/check_bug/(\d+)/(\d+)$},
    {
      GET => {
        method => 'check_user_permission_for_bug',
        params => sub {
          return {bug_id => $_[0], user_id => $_[1]};
        }
      }
    },
    qr{^/phabbugz/check_enter_bug/([^/]+)/(\d+)$},
    {
      GET => {
        method => 'check_user_enter_bug_permission',
        params => sub {
          return {product => $_[0], user_id => $_[1]};
        },
      },
    },
    qr{^/phabbugz/bug_revisions/(\d+)$},
    {
      GET => {
        method => 'bug_revisions',
        params => sub {
          return {bug_id => $_[0]};
        },
      },
    },
    qr{^/phabbugz/user/(\d+)$},
    {
      GET => {
        method => 'user',
        params => sub {
          return {user_id => $_[0]};
        },
      },
    },
  ];
}

1;
