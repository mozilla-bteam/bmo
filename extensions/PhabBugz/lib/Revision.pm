# This Source Code Form is hasject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Revision;

use 5.10.1;
use Moo;

use Mojo::JSON qw(true);
use Scalar::Util qw(blessed);
use Types::Standard -all;
use Type::Utils;

use Bugzilla::Bug;
use Bugzilla::Types qw(JSONBool);
use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Project;
use Bugzilla::Extension::PhabBugz::User;
use Bugzilla::Extension::PhabBugz::Types qw(:types);
use Bugzilla::Extension::PhabBugz::Util qw(request);

#########################
#    Initialization     #
#########################

has id               => (is => 'ro',   isa => Int);
has phid             => (is => 'ro',   isa => Str);
has title            => (is => 'ro',   isa => Str);
has summary          => (is => 'ro',   isa => Str);
has status           => (is => 'ro',   isa => Str);
has creation_ts      => (is => 'ro',   isa => Str);
has modification_ts  => (is => 'ro',   isa => Str);
has author_phid      => (is => 'ro',   isa => Str);
has diff_phid        => (is => 'ro',   isa => Str);
has bug_id           => (is => 'ro',   isa => Str);
has view_policy      => (is => 'ro',   isa => Str);
has edit_policy      => (is => 'ro',   isa => Str);
has subscriber_count => (is => 'ro',   isa => Int);
has bug              => (is => 'lazy', isa => Object);
has author           => (is => 'lazy', isa => Object);
has reviews =>
  (is => 'lazy', isa => ArrayRef [Dict [user => PhabUser | PhabProject, status => Str]]);
has subscribers => (is => 'lazy', isa => ArrayRef [PhabUser]);
has projects    => (is => 'lazy', isa => ArrayRef [Project]);
has reviewers_raw => (
  is  => 'ro',
  isa => ArrayRef [
    Dict [
      reviewerPHID => Str,
      status       => Str,
      isBlocking   => Bool | JSONBool,
      actorPHID    => Maybe [Str],
    ],
  ]
);
has subscribers_raw => (
  is  => 'ro',
  isa => Dict [
    subscriberPHIDs    => ArrayRef [Str],
    subscriberCount    => Int,
    viewerIsSubscribed => Bool | JSONBool,
  ]
);
has projects_raw => (is => 'ro', isa => Dict [projectPHIDs => ArrayRef [Str]]);
has reviewers_extra_raw => (
  is  => 'ro',
  isa => ArrayRef [
    Dict [reviewerPHID => Str, voidedPHID => Maybe [Str], diffPHID => Maybe [Str]]
  ]
);

sub new_from_query {
  my ($class, $params) = @_;

  my $data = {
    queryKey    => 'all',
    attachments => {projects => 1, reviewers => 1, subscribers => 1},
    constraints => $params
  };

  my $result = request('differential.revision.search', $data);
  if (exists $result->{result}{data} && @{$result->{result}{data}}) {
    $result = $result->{result}{data}[0];

    # Some values in Phabricator for bug ids may have been saved
    # white whitespace so we remove any here just in case.
    $result->{fields}->{'bugzilla.bug-id'}
      = $result->{fields}->{'bugzilla.bug-id'}
      ? trim($result->{fields}->{'bugzilla.bug-id'})
      : "";
    return $class->new($result);
  }

  return undef;
}

sub BUILDARGS {
  my ($class, $params) = @_;

  $params->{title}           = $params->{fields}->{title};
  $params->{summary}         = $params->{fields}->{summary};
  $params->{status}          = $params->{fields}->{status}->{value};
  $params->{creation_ts}     = $params->{fields}->{dateCreated};
  $params->{modification_ts} = $params->{fields}->{dateModified};
  $params->{author_phid}     = $params->{fields}->{authorPHID};
  $params->{diff_phid}       = $params->{fields}->{diffPHID};
  $params->{bug_id}          = $params->{fields}->{'bugzilla.bug-id'};
  $params->{view_policy}     = $params->{fields}->{policy}->{view};
  $params->{edit_policy}     = $params->{fields}->{policy}->{edit};
  $params->{reviewers_raw}   = $params->{attachments}->{reviewers}->{reviewers}
    // [];
  $params->{subscribers_raw} = $params->{attachments}->{subscribers};
  $params->{projects_raw}    = $params->{attachments}->{projects};
  $params->{reviewers_extra_raw}
    = $params->{attachments}->{'reviewers-extra'}->{'reviewers-extra'} // [];
  $params->{subscriber_count}
    = $params->{attachments}->{subscribers}->{subscriberCount};

  delete $params->{fields};
  delete $params->{attachments};

  return $params;
}

# {
#   "data": [
#     {
#       "id": 25,
#       "type": "DREV",
#       "phid": "PHID-DREV-uozm3ggfp7e7uoqegmc3",
#       "fields": {
#         "title": "Added .arcconfig",
#         "authorPHID": "PHID-USER-4wigy3sh5fc5t74vapwm",
#         "dateCreated": 1507666113,
#         "dateModified": 1508514027,
#         "policy": {
#           "view": "public",
#           "edit": "admin"
#         },
#         "bugzilla.bug-id": "1154784"
#       },
#       "attachments": {
#         "reviewers": {
#           "reviewers": [
#             {
#               "reviewerPHID": "PHID-USER-2gjdpu7thmpjxxnp7tjq",
#               "status": "added",
#               "isBlocking": false,
#               "actorPHID": null
#             },
#             {
#               "reviewerPHID": "PHID-USER-o5dnet6dp4dkxkg5b3ox",
#               "status": "rejected",
#               "isBlocking": false,
#               "actorPHID": "PHID-USER-o5dnet6dp4dkxkg5b3ox"
#             }
#           ]
#         },
#         "subscribers": {
#           "subscriberPHIDs": [],
#           "subscriberCount": 0,
#           "viewerIsSubscribed": true
#         },
#         "projects": {
#           "projectPHIDs": []
#         }
#       }
#     }
#   ],
#   "maps": {},
#   "query": {
#     "queryKey": null
#   },
#   "cursor": {
#     "limit": 100,
#     "after": null,
#     "before": null,
#     "order": null
#   }
# }

#########################
#     Modification      #
#########################

sub update {
  my ($self) = @_;

  my $data = {objectIdentifier => $self->phid, transactions => []};

  if ($self->{added_comments}) {
    foreach my $comment (@{$self->{added_comments}}) {
      push @{$data->{transactions}}, {type => 'comment', value => $comment};
    }
  }

  if ($self->{set_subscribers}) {
    push @{$data->{transactions}},
      {type => 'subscribers.set', value => $self->{set_subscribers}};
  }

  if ($self->{add_subscribers}) {
    push @{$data->{transactions}},
      {type => 'subscribers.add', value => $self->{add_subscribers}};
  }

  if ($self->{remove_subscribers}) {
    push @{$data->{transactions}},
      {type => 'subscribers.remove', value => $self->{remove_subscribers}};
  }

  if ($self->{set_reviewers}) {
    push @{$data->{transactions}},
      {type => 'reviewers.set', value => $self->{set_reviewers}};
  }

  if ($self->{add_reviewers}) {
    push @{$data->{transactions}},
      {type => 'reviewers.add', value => $self->{add_reviewers}};
  }

  if ($self->{remove_reviewers}) {
    push @{$data->{transactions}},
      {type => 'reviewers.remove', value => $self->{remove_reviewers}};
  }

  if ($self->{set_policy}) {
    foreach my $name ("view", "edit") {
      next unless $self->{set_policy}->{$name};
      push @{$data->{transactions}},
        {type => $name, value => $self->{set_policy}->{$name}};
    }
  }

  if ($self->{set_status}) {
    push(@{$data->{transactions}}, {type => $self->{set_status}, value => true});
  }

  if ($self->{add_projects}) {
    push(
      @{$data->{transactions}},
      {type => 'projects.add', value => $self->{add_projects}}
    );
  }

  if ($self->{remove_projects}) {
    push(
      @{$data->{transactions}},
      {type => 'projects.remove', value => $self->{remove_projects}}
    );
  }

  my $result = request('differential.revision.edit', $data);

  return $result;
}

#########################
#      Builders         #
#########################

sub _build_bug {
  my ($self) = @_;
  return $self->{bug} ||= Bugzilla::Bug->new({id => $self->bug_id, cache => 1});
}

sub _build_author {
  my ($self) = @_;
  return $self->{author} if $self->{author};
  my $phab_user
    = Bugzilla::Extension::PhabBugz::User->new_from_query({
    phids => [$self->author_phid]
    });
  if ($phab_user) {
    return $self->{author} = $phab_user;
  }
}

sub _build_reviews {
  my ($self) = @_;

  my %by_phid = map { $_->{reviewerPHID} => $_ } @{$self->reviewers_raw};
  my @users;
  foreach my $phid (keys %by_phid) {
    if ($phid =~ /^PHID-PROJ/) {
      push(@users,
        Bugzilla::Extension::PhabBugz::Project->new_from_query({phids => [$phid]}));
    }
    else {
      push(@users,
        Bugzilla::Extension::PhabBugz::User->new_from_query({phids => [$phid]}));
    }
  }

  my @reviewers;
  foreach my $user (@users) {
    my $reviewer_data = {user => $user, status => $by_phid{$user->phid}{status}};

    # Set to accepted-prior if the diffs reviewer are different and the reviewer status is accepted
    foreach my $reviewer_extra (@{$self->reviewers_extra_raw}) {
      if ($reviewer_extra->{reviewerPHID} eq $user->phid) {
        if ($reviewer_extra->{diffPHID}) {
          if ( $reviewer_data->{status} eq 'accepted'
            && $reviewer_extra->{diffPHID} ne $self->diff_phid)
          {
            $reviewer_data->{status} = 'accepted-prior';
          }
        }
      }
    }
    push @reviewers, $reviewer_data;
  }

  return \@reviewers;
}

sub _build_subscribers {
  my ($self) = @_;

  return $self->{subscribers} if $self->{subscribers};
  return [] unless $self->subscribers_raw->{subscriberPHIDs};

  my @phids;
  foreach my $phid (@{$self->subscribers_raw->{subscriberPHIDs}}) {
    push @phids, $phid;
  }

  my $users = Bugzilla::Extension::PhabBugz::User->match({phids => \@phids});

  return $self->{subscribers} = $users;
}

sub _build_projects {
  my ($self) = @_;

  return $self->{projects} if $self->{projects};
  return [] unless $self->projects_raw->{projectPHIDs};

  my @projects;
  foreach my $phid (@{$self->projects_raw->{projectPHIDs}}) {
    push @projects,
      Bugzilla::Extension::PhabBugz::Project->new_from_query({phids => [$phid]});
  }

  return $self->{projects} = \@projects;
}

#########################
#       Mutators        #
#########################

sub add_comment {
  my ($self, $comment) = @_;
  $comment = trim($comment);
  $self->{added_comments} ||= [];
  push @{$self->{added_comments}}, $comment;
}

sub add_reviewer {
  my ($self, $reviewer) = @_;
  $self->{add_reviewers} ||= [];
  my $reviewer_phid = blessed $reviewer ? $reviewer->phid : $reviewer;
  push @{$self->{add_reviewers}}, $reviewer_phid;
}

sub remove_reviewer {
  my ($self, $reviewer) = @_;
  $self->{remove_reviewers} ||= [];
  my $reviewer_phid = blessed $reviewer ? $reviewer->phid : $reviewer;
  push @{$self->{remove_reviewers}}, $reviewer_phid;
}

sub set_reviewers {
  my ($self, $reviewers) = @_;
  $self->{set_reviewers} = [map { $_->phid } @$reviewers];
}

sub add_subscriber {
  my ($self, $subscriber) = @_;
  $self->{add_subscribers} ||= [];
  my $subscriber_phid = blessed $subscriber ? $subscriber->phid : $subscriber;
  push @{$self->{add_subscribers}}, $subscriber_phid;
}

sub remove_subscriber {
  my ($self, $subscriber) = @_;
  $self->{remove_subscribers} ||= [];
  my $subscriber_phid = blessed $subscriber ? $subscriber->phid : $subscriber;
  push @{$self->{remove_subscribers}}, $subscriber_phid;
}

sub set_subscribers {
  my ($self, $subscribers) = @_;
  $self->{set_subscribers} = $subscribers;
}

sub set_policy {
  my ($self, $name, $policy) = @_;
  $self->{set_policy} ||= {};
  $self->{set_policy}->{$name} = $policy;
}

sub set_status {
  my ($self, $status) = @_;
  $self->{set_status} = $status;
}

sub add_project {
  my ($self, $project) = @_;
  $self->{add_projects} ||= [];
  my $project_phid = blessed $project ? $project->phid : $project;
  return undef unless $project_phid;
  push @{$self->{add_projects}}, $project_phid;
}

sub remove_project {
  my ($self, $project) = @_;
  $self->{remove_projects} ||= [];
  my $project_phid = blessed $project ? $project->phid : $project;
  return undef unless $project_phid;
  push @{$self->{remove_projects}}, $project_phid;
}

sub make_private {
  my ($self, $project_names) = @_;

  my $secure_revision_project
    = Bugzilla::Extension::PhabBugz::Project->new_from_query({
    name => 'secure-revision'
    });

  my @set_projects;
  foreach my $name (@$project_names) {
    my $set_project
      = Bugzilla::Extension::PhabBugz::Project->new_from_query({name => $name});
    push @set_projects, $set_project;
  }

  my $new_policy = Bugzilla::Extension::PhabBugz::Policy->create(\@set_projects);
  $self->set_policy('view', $new_policy->phid);
  $self->set_policy('edit', $new_policy->phid);

  foreach my $project ($secure_revision_project, @set_projects) {
    $self->add_project($project->phid);
  }

  return $self;
}

sub make_public {
  my ($self) = @_;

  my $editbugs
    = Bugzilla::Extension::PhabBugz::Project->new_from_query({
    name => 'bmo-editbugs-team'
    });

  $self->set_policy('view', 'public');
  $self->set_policy('edit', ($editbugs ? $editbugs->phid : 'users'));

  my @current_group_projects
    = grep { $_->name =~ /^(bmo-.*|secure-revision)$/ } @{$self->projects};
  foreach my $project (@current_group_projects) {
    $self->remove_project($project->phid);
  }

  return $self;
}

1;
