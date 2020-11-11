# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Bugzilla;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util qw(datetime_from);
use JSON::XS;
use Try::Tiny;

use DateTime;

# Basic info that is needed before logins
use constant LOGIN_EXEMPT => {timezone => 1, version => 1,};

sub version {
  my $self = shift;
  return {version => $self->type('string', BUGZILLA_VERSION)};
}

sub extensions {
  my $self = shift;

  my %retval;
  foreach my $extension (@{Bugzilla->extensions}) {
    my $version = $extension->VERSION || 0;
    my $name    = $extension->NAME;
    $retval{$name}->{version} = $self->type('string', $version);
  }
  return {extensions => \%retval};
}

sub timezone {
  my $self = shift;

  # All Webservices return times in UTC; Use UTC here for backwards compat.
  return {timezone => $self->type('string', "+0000")};
}

sub time {
  my ($self) = @_;

  # All Webservices return times in UTC; Use UTC here for backwards compat.
  # Hardcode values where appropriate
  my $dbh = Bugzilla->dbh;

  my $db_time = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
  $db_time = datetime_from($db_time, 'UTC');
  my $now_utc = DateTime->now();

  return {
    db_time       => $self->type('dateTime', $db_time),
    web_time      => $self->type('dateTime', $now_utc),
    web_time_utc  => $self->type('dateTime', $now_utc),
    tz_name       => $self->type('string',   'UTC'),
    tz_offset     => $self->type('string',   '+0000'),
    tz_short_name => $self->type('string',   'UTC'),
  };
}

sub jobqueue_status {
  my ($self, $params) = @_;

  Bugzilla->login(LOGIN_REQUIRED);

  my $dbh   = Bugzilla->dbh;
  my $query = q{
        SELECT
            COUNT(*) AS total,
            COALESCE(
                (SELECT COUNT(*)
                    FROM ts_error
                    WHERE ts_error.jobid = j.jobid
                )
            , 0) AS errors
        FROM ts_job j
            INNER JOIN ts_funcmap f
                ON f.funcid = j.funcid
        GROUP BY errors
    };

  my $status;
  try {
    $status           = $dbh->selectrow_hashref($query);
    $status->{errors} = 0 + $status->{errors};
    $status->{total}  = 0 + $status->{total};
  }
  catch {
    ERROR($_);
    ThrowCodeError('jobqueue_status_error');
  };

  return $status;
}

1;

