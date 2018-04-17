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

use Bugzilla::Constants;
use Bugzilla::User;

use Bugzilla::Extension::PhabBugz::Constants;

use constant PUBLIC_METHODS => qw(
    check_user_permission_for_bug
);

sub check_user_permission_for_bug {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Ensure PhabBugz is on
    ThrowUserError('phabricator_not_enabled')
        unless Bugzilla->params->{phabricator_enabled};

    # Validate that the requesting user's email matches phab-bot
    ThrowUserError('phabricator_unauthorized_user')
        unless $user->login eq PHAB_AUTOMATION_USER;
    
    # Validate that a bug id and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{bug_id} && $params->{user_id});

    # Validate that the user and bug exist
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object which says { "result": 1|0 }
    return {
        result => $target_user->can_see_bug($params->{bug_id})
    };
}

sub rest_resources {
    return [
        # Bug permission checks
        qr{^/phabbugz/check_bug/(\d+)/(\d+)$}, {
            GET => {
                method => 'check_user_permission_for_bug',
                params => sub {
                    return { bug_id => $_[0], user_id => $_[1] };
                }
            }
        },
    ];
}

1;
