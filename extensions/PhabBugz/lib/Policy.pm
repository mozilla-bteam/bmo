# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Policy;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Util qw(request);
use Bugzilla::Extension::PhabBugz::Project;

use List::Util qw(first);

use Types::Standard -all;
use Type::Utils;

my $SearchResult = Dict[
    phid      => Str,
    type      => Str,
    name      => Str,
    shortName => Str,
    fullName  => Str,
    href      => Maybe[Str],
    workflow  => Maybe[Str],
    icon      => Str,
    default   => Str,
    rules     => ArrayRef[
        Dict[
            action => Str,
            rule   => Str,
            value  => Maybe[ArrayRef[Str]]
        ]
    ]
];

# {
#   "data": [
#     {
#       "phid": "PHID-PLCY-l2mt4yeq4byqgcot7x4j",
#       "type": "custom",
#       "name": "Custom Policy",
#       "shortName": "Custom Policy",
#       "fullName": "Custom Policy",
#       "href": null,
#       "workflow": null,
#       "icon": "fa-certificate",
#       "default": "deny",
#       "rules": [
#         {
#           "action": "allow",
#           "rule": "PhabricatorSubscriptionsSubscribersPolicyRule",
#           "value": null
#         },
#         {
#           "action": "allow",
#           "rule": "PhabricatorProjectsPolicyRule",
#           "value": [
#             "PHID-PROJ-cvurjiwfvh756mv2vhvi"
#           ]
#         }
#       ]
#     }
#   ],
#   "cursor": {
#     "limit": 100,
#     "after": null,
#     "before": null
#   }
# }

#########################
#    Initialization     #
#########################

sub new {
    my ($class, $params) = @_;
    my $results = $class->match($params);
    return $results->[0];
}

sub match {
    my ($invocant, $constraints) = @_;
    my $class = ref($invocant) || $invocant;

    my $policies;
    my $result = request('policy.query', $constraints);
    if (exists $result->{result}{data} && @{ $result->{result}{data} }) {
        $policies = $result->{result}{data};
    }

    foreach my $policy (@$policies) {
        $SearchResult->assert_valid($policy);
    }

    return [ map { bless($_, $class) } @$policies ];
}

#########################
#     Modification      #
#########################

sub create {
    my ($class, $projects) = @_;

    my $data = {
        objectType => 'DREV',
        default    => 'deny',
        policy     => [
            {
                action => 'allow',
                rule   => 'PhabricatorSubscriptionsSubscribersPolicyRule',
            }
        ]
    };

    if(scalar @$projects gt 0) {
        my $project_phids = [];
        foreach my $project_name (@$projects) {
            my $project = Bugzilla::Extension::PhabBugz::Project->new({ name => $project_name });
            push(@$project_phids, $project->phid) if $project;
        }

        ThrowUserError('invalid_phabricator_sync_groups') unless @$project_phids;

        push(@{ $data->{policy} },
            {
                action => 'allow',
                rule   => 'PhabricatorProjectsPolicyRule',
                value  => $project_phids,
            }
        );
    }
    else {
        push(@{ $data->{policy} },
            {
                action => 'allow',
                value  => 'admin',
            }
        );
    }

    my $result = request('policy.create', $data);
    return $class->new({ phids => [ $result->{result}{phid} ] });
}

#########################
#      Accessors        #
#########################

sub phid    { return $_[0]->{phid};    }
sub type    { return $_[0]->{type};    }
sub name    { return $_[0]->{name};    }
sub icon    { return $_[0]->{icon};    }
sub default { return $_[0]->{default}; }
sub rules   { return $_[0]->{rules};   }

sub get_rule_projects {
    my ($self) = @_;
    return $self->{rule_projects} if $self->{rule_projects};
    $self->{rule_projects} ||= [];
    if ($self->rules) {
        if (my $rule = first { $_->{rule} eq 'PhabricatorProjectsPolicyRule'} @{ $self->rules }) {
            foreach my $phid (@{ $rule->{value} }) {
                my $project = Bugzilla::Extension::PhabBugz::Project->new({ phids => [ $phid ] });
                if ($project) {
                    push(@{ $self->{rule_projects} }, $project->name);
                }
            }
        }
    }
    return $self->{rule_projects};
}

1;