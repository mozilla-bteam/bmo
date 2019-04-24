# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Report::InactiveUser;
use 5.10.1;
use Moo;

use Bugzilla::Logging;
use Bugzilla::Types qw(User);
use Type::Utils;
use Types::Standard qw(:types);

has 'users' => ( is => 'lazy', isa      => ArrayRef [User] );
has 'dbh'   => ( is => 'ro',   required => 1 );

# https://metacpan.org/pod/distribution/DBIx-Class/lib/DBIx/Class/Manual/DocMap.pod
# TODO: double check that last_seen applies to api requests

# first criteria: last_seen is null OR more than 12 months old
# ignore emails ending in netscape*** or mozilla.org or mozilla.com or mozillafoundation.org or getpocket
# REMOVE ME:
#  SELECT * FROM profiles WHERE last_seen_date IS NULL LIMIT 1000
#  SELECT COUNT(userid) FROM profiles WHERE last_seen_date IS NULL; --

# Verify the ~470000 results returned
# Figure out how to process these without using up too memory (paging somehow)
# Load entire list ~ 12megs (depending on if it's really 470000)
# load the actual user models in batches
sub _build_users {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $query = qq{
      SELECT COUNT(userid)
      FROM profiles
      WHERE
        ( last_seen_date IS NULL
          OR last_seen_date > @{[  $dbh->sql_date_math('NOW()', '-', 1, 'YEAR') ]})
        AND NOT (
          login_name LIKE '%\@mozilla.com'
          OR  login_name LIKE '%\@mozilla.org'
          OR  login_name LIKE '%\@getpocket.com'
          OR  login_name LIKE '%\@mozillafoundation.org'
          OR  login_name LIKE '%\@formerly-netscape.com.tld'
          OR  login_name LIKE '%\@bugzilla.org'
        )
      AND login_name <> 'nobody\@mozilla.com'
    };
    # LIMT 1000
    DEBUG("sql: $query");

    # ARRAY1 = [ [ 1 ] ];
    my $users = $dbh->selectcol_arrayref($query);
    use Data::Dumper;
    WARN(Dumper($users));
    exit;
    return Bugzilla::User->new_from_list($users);
}

1;
