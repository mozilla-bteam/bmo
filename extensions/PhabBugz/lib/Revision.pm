# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Revision;

use 5.10.1;

use Moo;

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Util qw(
    request
    get_members_by_phid
);

use parent qw(Bugzilla::Object);

#########################
#    Initialization     #
#########################

# This is an external object so we do not want any auditing.
use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;

sub new {
    my ($class, $params) = @_;
    my $self = $params ? _load($params) : {};
    bless($self, $class);
    return $self;
}

sub _load {
    my ($params) = @_;

    my $data = {
        queryKey    => 'all',
        attachments => {
            projects    => 1,
            reviewers   => 1,
            subscribers => 1
        }
    };

    if ($params->{ids}) {
        $data->{constraints} = {
            ids => $params->{ids}
        };
    }
    elsif ($params->{phids}) {
        $data->{constraints} = {
            phids => $params->{phids}
        };
    }
    else {
        ThrowUserError('invalid_phabricator_revision_id');
    }

    my $result = request('differential.revision.search', $data);

    ThrowUserError('invalid_phabricator_revision_id')
        unless (exists $result->{result}{data} && @{ $result->{result}{data} });

    return $result->{result}->{data}->[0];
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

    if ($self->{added_comments}) {
        foreach my $comment (@{ $self->{added_comments} }) {
            my $data = {
                transactions => [
                    {
                        type  => 'comment',
                        value => $comment
                    }
                ],
                objectIdentifier => $self->phid
            };
            my $result = request('differential.revision.edit', $data);
        }
    }

    if ($self->{set_subscribers}) {
        my $data = {
            transactions => [
                {
                    type  => 'subscribers.set',
                    value => $self->{set_subscribers}
                }
            ],
            objectIdentifier => $self->phid
        };

        my $result = request('differential.revision.edit', $data);
    }
}

#########################
#      Accessors        #
#########################

sub id              { return $_[0]->{id};                          }
sub phid            { return $_[0]->{phid};                        }
sub title           { return $_[0]->{fields}->{title};             }
sub creation_ts     { return $_[0]->{fields}->{dateCreated};       }
sub modification_ts { return $_[0]->{fields}->{dateModified};      }
sub author_phid     { return $_[0]->{fields}->{authorPHID};        }
sub bug_id          { return $_[0]->{fields}->{'bugzilla.bug-id'}; }

sub view_policy { return $_[0]->{fields}->{policy}->{view}; }
sub edit_policy { return $_[0]->{fields}->{policy}->{edit}; }

sub reviewers_raw    { return $_[0]->{atachments}->{reviewers}->{reviewers};          }
sub subscribers_raw  { return $_[0]->{attachments}->{subscribers};                    }
sub projects_raw     { return $_[0]->{attachments}->{projects};                       }
sub subscriber_count { return $_[0]->{attachments}->{subscribers}->{subscriberCount}; }

sub bug {
    my $self = shift;
    my $bug = $self->{bug} ||= new Bugzilla::Bug($self->bug_id);
    weaken($self->{bug}) unless isweak($self->{bug});
    return $bug;
}

sub author {
    my $self = shift;
    return $self->{author} if $self->{author};
    my $userids = get_members_by_phid([$self->author_phid]);
    $self->{'author'} = new Bugzilla::User({ id => $userids->[0], cache => 1 });
    return $self->{'author'};
}

sub reviewers {
    my ($self) = @_;
    return $self->{reviewers} if $self->{reviewers};

    my @phids;
    foreach my $reviewer (@{ $self->reviewers_raw }) {
        push(@phids, $reviewer->{reviewerPHID});
    }

    my $userids = get_members_by_phid(\@phids);

    my @reviewers;
    my $i = 0;
    foreach my $userid (@$userids) {
        my $reviewer = Bugzilla::User->new({ id => $userid, cache => 1});
        $reviewer->{phab_review_status} = $self->reviewers_raw->[$i]->{status};
        $reviewer->{phab_phid} = $self->reviewers_raw->[$i]->{reviewerPHID};
        push(@reviewers, $reviewer);
        $i++;
    }

    return \@reviewers;
}

sub subscribers {
    my ($self) = @_;
    return $self->{subscribers} if $self->{subscribers};

    my @phids;
    foreach my $phid (@{ $self->subscribers_raw->{subscriberPHIDs} }) {
        push(@phids, $phid);
    }

    my $userids = get_members_by_phid(\@phids);

    my @subscribers;
    my $i = 0;
    foreach my $userid (@$userids) {
        my $subscriber = Bugzilla::User->new({ id => $userid, cache => 1});
        $subscriber->{phab_phid} = $self->subscribers_raw->{subscriberPHIDs}->[$i];
        push(@subscribers, $subscriber);
        $i++;
    }

    return \@subscribers;

}

#########################
#       Mutators        #
#########################

sub add_comment {
    my ($self, $comment) = @_;
    $comment = trim($comment);
    $self->{added_comments} ||= [];
    push(@{ $self->{added_comments} }, $comment);
}

sub set_subscribers {
    my ($self, $subscribers) = @_;
    $self->{set_subscribers} = $subscribers;
}

1;