# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Util;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;

use Data::Dumper;
use JSON qw(encode_json decode_json);
use LWP::UserAgent;

use base qw(Exporter);

our @EXPORT = qw(
    create_private_revision_policy
    create_project
    edit_revision_policy
    get_members_by_bmo_id
    get_project_phid
    intersect
    make_revision_public
    request
    set_project_members
);

sub intersect {
    my ($list1, $list2) = @_;
    my %e = map { $_ => undef } @{$list1};
    return grep { exists( $e{$_} ) } @{$list2};
}

sub create_private_revision_policy {
    my ($bug, $groups) = @_;

    my $project_phids = [];
    foreach my $group (@$groups) {
        my $phid = get_project_phid('bmo-' . $group);
        push(@$project_phids, $phid) if $phid;
    }

    @$project_phids
        || ThrowUserError('invalid_phabricator_sync_groups');
    my $user_phids = []; #FIXME

    my $data = {
        objectType => 'DREV',
        default    => 'deny',
        policy     => [
            {
                action => 'allow',
                rule   => 'PhabricatorProjectsPolicyRule',
                value  => $project_phids,
            },
#            {
#                action => 'allow',
#                rule   => 'PhabricatorUsersPolicyRule',
#                value  => $user_phids,
#            }
        ]
    };

    my $result = request('policy.create', $data);
    return $result->{result}{phid};
}

sub make_revision_public {
    my ($revision_phid) = @_;
    return request('differential.revision.edit', {
        transactions => [
            {
                type  => "view",
                value => "users"
            }
        ],
        objectIdentifier => $revision_phid
    });
}

sub edit_revision_policy {
    my ($revision_phid, $policy_phid) = @_;

    my $data = {
        transactions => [
            {
                type  => 'view',
                value => $policy_phid
            }
        ],
        objectIdentifier => $revision_phid
    };

    return request('differential.revision.edit', $data);
}

sub get_project_phid {
    my $project = shift;

    my $data = {
        queryKey => 'active',
        constraints => {
            name => $project
        }
    };

    my $result = request('project.search', $data);
    if (!$result->{result}{data}) {
        return undef;
    }
    return $result->{result}{data}[0]{phid};
}

sub create_project {
    my ($project, $description, $members) = @_;

    my $data = {
        transactions => [
            { type => 'name',  value => $project           },
            { type => 'description', value => $description },
            { type => 'edit',  value => 'admin'            },
            { type => 'join',  value => 'admin'            },
            { type => 'view',  value => 'admin'            },
            { type => 'icon',  value => 'group'            },
            { type => 'color', value => 'red'              }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub set_project_members {
    my ($project_id, $phab_user_ids) = @_;

    my $data = {
        objectIdentifier => $project_id,
        transactions => [
            { type => 'members.set',  value => $phab_user_ids }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub get_members_by_bmo_id {
    my $users = shift;

    my $data = {
        accountids => [ map { $_->id } @$users ]
    };

    my $result = request('bmoexternalaccount.search', $data);
    if (!$result->{result}) {
        return [];
    }

    my @phab_ids;
    foreach my $user (@{ $result->{result} }) {
        push(@phab_ids, $user->{phid});
    }
    return \@phab_ids;
}

sub request {
    my ($method, $data) = @_;

    my $phab_api_key  = Bugzilla->params->{phabricator_api_key};
    my $phab_base_uri = Bugzilla->params->{phabricator_base_uri};
    $phab_base_uri || ThrowUserError('invalid_phabricator_uri');
    $phab_api_key  || ThrowUserError('invalid_phabricator_api_key');

    state $ua;

    if (!$ua) {
        $ua = LWP::UserAgent->new(timeout => 10);
        if (Bugzilla->params->{proxy_url}) {
            $ua->proxy('https', Bugzilla->params->{proxy_url});
        }
        $ua->default_header('Content-Type' => 'application/x-www-form-urlencoded');
    }

    my $full_uri = $phab_base_uri . '/api/' . $method;

    $data->{__conduit__} = { token => $phab_api_key };

    my $response = eval {
        $ua->post($full_uri, { params => encode_json($data) });
    };

    $response->is_error
        && ThrowCodeError('phabricator_api_error',
                          { reason => $response->message });

    my $result = decode_json($response->content);
    if ($result->{error_code}) {
        ThrowCodeError('phabricator_api_error',
                       { code   => $result->{error_code},
                         reason => $result->{error_info} });
    }
    return $result;
}

1;
