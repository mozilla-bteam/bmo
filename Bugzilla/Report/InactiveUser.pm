# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::InactiveUser;
use 5.10.1;
use Moo;

use Data::Dumper; # TODO remove me

use Bugzilla::Logging;
use Bugzilla::Types qw(User);
use Type::Utils;
use Types::Standard qw(:types);

has 'dbh'     => (is => 'ro',   required => 1);
has 'userids' => (is => 'lazy', isa      => ArrayRef [Int]);

# TODO: double check that last_seen applies to api requests
# TODO: ignore users with email in the badhosts
# TODO: should we ignore .tld and .bugs?
sub _build_userids {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $query = qq{
      SELECT userid
      FROM profiles
      WHERE
        (
          last_seen_date IS NULL
          OR last_seen_date > @{[  $dbh->sql_date_math('NOW()', '-', 1, 'YEAR') ]}
        )
        AND NOT (
          login_name LIKE '%\@mozilla.com'
          OR  login_name LIKE '%\@mozilla.org'
          OR  login_name LIKE '%\@getpocket.com'
          OR  login_name LIKE '%\@mozillafoundation.org'
          OR  login_name LIKE '%\@formerly-netscape.com.tld'
          OR  login_name LIKE '%\@bugzilla.org'
        )
        AND login_name <> 'nobody\@mozilla.com'
        AND userid NOT IN ( SELECT DISTINCT who FROM bugs_activity )
        AND userid NOT IN ( SELECT DISTINCT who FROM longdescs )
        AND disabledtext = ''
        ORDER BY userid
    };

    my $userids = $dbh->selectcol_arrayref($query);
    # WARN(Dumper($userids));
    sleep;
    return $userids;

    #return Bugzilla::User->new_from_list($users);
}

1;
