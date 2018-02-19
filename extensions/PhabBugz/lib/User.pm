# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::User;

use 5.10.1;
use Moo;

use Bugzilla::User;

use Bugzilla::Extension::PhabBugz::Util qw(request);

use Types::Standard -all;
use Type::Utils;

#########################
#    Initialization     #
#########################

has 'id'              => ( is => 'ro', isa => Int );
has 'type'            => ( is => 'ro', isa => Str );
has 'phid'            => ( is => 'ro', isa => Str );
has 'name'            => ( is => 'ro', isa => Str );
has 'realname'        => ( is => 'ro', isa => Str );
has 'creation_ts'     => ( is => 'ro', isa => Int );
has 'modification_ts' => ( is => 'ro', isa => Int );
has 'roles'           => ( is => 'ro', isa => ArrayRef [Str] );
has 'view_policy'     => ( is => 'ro', isa => Str );
has 'edit_policy'     => ( is => 'ro', isa => Str );
has 'bugzilla_id'     => ( is => 'ro', isa => Maybe [Int] );

sub BUILDARGS {
    my ( $class, $params ) = @_;

    $params->{name}            = $params->{fields}->{username};
    $params->{realname}        = $params->{fields}->{realName};
    $params->{creation_ts}     = $params->{fields}->{dateCreated};
    $params->{modification_ts} = $params->{fields}->{dateModified};
    $params->{roles}           = $params->{fields}->{roles};
    $params->{view_policy}     = $params->{fields}->{policy}->{view};
    $params->{edit_policy}     = $params->{fields}->{policy}->{edit};

    delete $params->{fields};

    if ( my $external_accounts =
        $params->{attachments}{'external-accounts'}{'external-accounts'} )
    {
        foreach my $account (@$external_accounts) {
            next if $account->{type} ne 'bmo';
            $params->{bug_user_id} = $account->{id};
            last;
        }
    }

    delete $params->{attachments};

    return $params;
}

# {
#   "data": [
#     {
#       "id": 2,
#       "type": "USER",
#       "phid": "PHID-USER-h4aqihzqsnytz7nsegsr",
#       "fields": {
#         "username": "phab-bot",
#         "realName": "Phabricator Automation",
#         "roles": [
#           "admin",
#           "verified",
#           "approved",
#           "activated"
#         ],
#         "dateCreated": 1512573120,
#         "dateModified": 1512574523,
#         "policy": {
#           "view": "public",
#           "edit": "no-one"
#         }
#       },
#       "attachments": {
#         "external-accounts": {
#           "external-accounts": [
#             {
#               "id": "9",
#               "type": "bmo"
#             }
#           ]
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

sub new_from_query {
    my ( $class, $params ) = @_;
    my ($user) = $class->match($params);
    return $user;
}

sub match {
    my ( $class, $params ) = @_;

    # BMO id search takes precedence if bugzilla_ids is used.
    my $bugzilla_ids = delete $params->{bugzilla_ids};
    if ($bugzilla_ids) {
        my $bugzilla_data =
          $class->get_phab_bugzilla_ids( { ids => $bugzilla_ids } );
        $params->{phids} = [ map { $_->{phid} } @$bugzilla_data ];
    }

    return [] if !@{ $params->{phids} };

    # Look for BMO external user id in external-accounts attachment
    my $data = {
        constraints => { phids             => $params->{phids} },
        attachments => { external_accounts => 1 }
    };

    my $phab_users = [];
    my $result = request( 'user.search', $data );

    if ( exists $result->{result}{data} && @{ $result->{result}{data} } ) {
        foreach my $user ( @{ $result->{result}{data} } ) {
            push @$phab_users, $class->new($user);
        }
    }

    return $phab_users;
}

#################
#   Accessors   #
#################

sub bugzilla_user {
    my ($self) = @_;
    return undef if !$self->bugzilla_id;
    return $self->{bugzilla_user} ||=
      Bugzilla::User->new( { id => $self->bugzilla_id, cache => 1 } );
}

sub get_phab_bugzilla_ids {
    my ( $class, $params ) = @_;

    my $memcache = Bugzilla->memcached;

    # Try to find the values in memcache first
    my @results;
    my @bugzilla_ids = @{ $params->{ids} };
    for ( my $i = 0 ; $i < @bugzilla_ids ; $i++ ) {
        my $phid =
          $memcache->get(
            { key => "phab_user_bugzilla_id_" . $bugzilla_ids[$i] } );
        if ($phid) {
            push(
                @results,
                {
                    id   => $bugzilla_ids[$i],
                    phid => $phid
                }
            );
            splice( @bugzilla_ids, $i, 1 );
        }
    }

    if (@bugzilla_ids) {
        $params->{ids} = \@bugzilla_ids;

        my $result = request( 'bugzilla.account.search', $params );

        # Store new values in memcache for later retrieval
        foreach my $user ( @{ $result->{result} } ) {
            $memcache->set(
                {
                    key   => "phab_user_bugzilla_id_" . $user->{id},
                    value => $user->{phid}
                }
            );
            push( @results, $user );
        }
    }

    return \@results;
}

1;

