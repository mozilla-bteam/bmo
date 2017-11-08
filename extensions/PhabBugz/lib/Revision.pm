 # This Source Code Form is hasject to the terms of the Mozilla Public
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
    get_phab_bmo_ids
    request
);

#########################
#    Initialization     #
#########################

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

    # If proper ids and phids constraints were
    # provided, we return an empty data structure
    # instead of failing outright. This allows for
    # silently checking for the existence of a
    # revision.
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
        return {};
    }

    my $result = request('differential.revision.search', $data);
    if (exists $result->{result}{data} && @{ $result->{result}{data} }) {
        return $result->{result}->{data}->[0];
    }

    return {};
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

    my $data = {
        objectIdentifier => $self->phid,
        transactions     => []
    };

    if ($self->{added_comments}) {
        foreach my $comment (@{ $self->{added_comments} }) {
            push(@{ $data->{transactions} }, {
                type  => 'comment',
                value => $comment
            });
        }
    }

    if ($self->{set_subscribers}) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.set',
            value => $self->{set_subscribers}
        });
    }

    if ($self->{set_policy}) {
        foreach my $name ("view", "edit") {
            next unless $self->{set_policy}->{$name};
            push(@{ $data->{transactions} }, {
                type  => $name,
                value => $self->{set_policy}->{$name}
            });
        }
    }

    request('differential.revision.edit', $data);
}

#########################
#      Accessors        #
#########################

sub id              { $_[0]->{id};                          }
sub phid            { $_[0]->{phid};                        }
sub title           { $_[0]->{fields}->{title};             }
sub status          { $_[0]->{fields}->{status}->{value};   }
sub creation_ts     { $_[0]->{fields}->{dateCreated};       }
sub modification_ts { $_[0]->{fields}->{dateModified};      }
sub author_phid     { $_[0]->{fields}->{authorPHID};        }
sub bug_id          { $_[0]->{fields}->{'bugzilla.bug-id'}; }

sub view_policy { $_[0]->{fields}->{policy}->{view}; }
sub edit_policy { $_[0]->{fields}->{policy}->{edit}; }

sub reviewers_raw    { $_[0]->{attachments}->{reviewers}->{reviewers};          }
sub subscribers_raw  { $_[0]->{attachments}->{subscribers};                    }
sub projects_raw     { $_[0]->{attachments}->{projects};                       }
sub subscriber_count { $_[0]->{attachments}->{subscribers}->{subscriberCount}; }

sub bug {
    my ($self) = @_;
    my $bug = $self->{bug} ||= new Bugzilla::Bug($self->bug_id);
    weaken($self->{bug}) unless isweak($self->{bug});
    return $bug;
}

sub author {
    my ($self) = @_;
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

    return [] if !@phids;

    my $users = get_phab_bmo_ids({ phids => \@phids });

    my @reviewers;
    foreach my $user (@$users) {
        my $reviewer = Bugzilla::User->new({ id => $user->{id}, cache => 1});
        $reviewer->{phab_phid} = $user->{phid};
        foreach my $reviewer_data (@{ $self->reviewers_raw }) {
            if ($reviewer_data->{reviewerPHID} eq $user->{phid}) {
                $reviewer->{phab_review_status} = $reviewer_data->{status};
                last;
            }
        }
        push(@reviewers, $reviewer);
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

    my $users = get_phab_bmo_ids({ phids => \@phids });

    return [] if !@phids;

    my @subscribers;
    foreach my $user (@$users) {
        my $subscriber = Bugzilla::User->new({ id => $user->{id}, cache => 1});
        $subscriber->{phab_phid} = $user->{phid};
        push(@subscribers, $subscriber);
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

sub set_policy {
    my ($self, $name, $policy) = @_;
    $self->{set_policy} ||= {};
    $self->{set_policy}->{$name} = $policy;
}

1;