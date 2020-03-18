# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::Bugzilla;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Keyword;
use Bugzilla::Logging;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Util qw(datetime_from);
use JSON::XS;
use Try::Tiny;

use DateTime;

# Basic info that is needed before logins
use constant LOGIN_EXEMPT => {timezone => 1, version => 1,};

use constant READ_ONLY => qw(
  configuration
  extensions
  timezone
  time
  version
  jobqueue_status
);

use constant PUBLIC_METHODS => qw(
  configuration
  extensions
  time
  timezone
  version
  jobqueue_status
);

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

sub configuration {
  my ($self) = @_;
  my $user   = Bugzilla->user;
  my $params = Bugzilla->input_params;

  my $can_cache = !exists $params->{product} && !exists $params->{flags};

# Using config.* will clear this data in memcache when Bugzilla changes are made to products, components, etc.
  my $cache_key = 'config.configuration';
  if ($can_cache) {
    my $result = Bugzilla->memcached->get_config({key => $cache_key});
    return $result if defined $result;
  }

  # Get data from the shadow DB as they don't change very often.
  Bugzilla->switch_to_shadow_db;

  # Pass a bunch of Bugzilla configuration to the templates.
  my $vars = {};
  $vars->{'type'}       = get_legal_field_values('bug_type');
  $vars->{'priority'}   = get_legal_field_values('priority');
  $vars->{'severity'}   = get_legal_field_values('bug_severity');
  $vars->{'platform'}   = get_legal_field_values('rep_platform');
  $vars->{'op_sys'}     = get_legal_field_values('op_sys');
  $vars->{'keyword'}    = [map($_->name, Bugzilla::Keyword->get_all)];
  $vars->{'resolution'} = get_legal_field_values('resolution');
  $vars->{'status'}     = get_legal_field_values('bug_status');
  $vars->{'custom_fields'}
    = [grep { $_->is_select } Bugzilla->active_custom_fields];

  # Include a list of product objects.
  if ($params->{'product'}) {
    my @products = $params->{'product'};
    foreach my $product_name (@products) {
      my $product = Bugzilla::Product->new({name => $product_name});
      if ($product && $user->can_see_product($product->name)) {
        push(@{$vars->{'products'}}, $product);
      }
    }
  }
  else {
    $vars->{'products'} = $user->get_selectable_products;
  }

  # We set the 2nd argument to 1 to also preload flag types.
  Bugzilla::Product::preload($vars->{'products'}, 1, {is_active => 1});

  # Allow consumers to specify whether or not they want flag data.
  if (defined $params->{'flags'}) {
    $vars->{'show_flags'} = $params->{'flags'};
  }
  else {
    # We default to sending flag data.
    $vars->{'show_flags'} = 1;
  }

  # Create separate lists of open versus resolved statuses.  This should really
  # be made part of the configuration.
  my @open_status;
  my @closed_status;
  foreach my $status (@{$vars->{'status'}}) {
    is_open_state($status)
      ? push(@open_status,   $status)
      : push(@closed_status, $status);
  }
  $vars->{'open_status'}   = \@open_status;
  $vars->{'closed_status'} = \@closed_status;

  # Generate a list of fields that can be queried.
  my @fields = @{Bugzilla::Field->match({obsolete => 0})};

  # Exclude fields the user cannot query.
  if (!Bugzilla->user->is_timetracker) {
    @fields = grep {
      $_->name
        !~ /^(estimated_time|remaining_time|work_time|percentage_complete|deadline)$/
    } @fields;
  }
  $vars->{'field'} = \@fields;

  my $json;
  Bugzilla->template->process('config.json.tmpl', $vars, \$json);
  if ($json) {
    my $result = JSON::XS->new->boolean_values(0, 1)->decode($json);
    if ($can_cache) {
      Bugzilla->memcached->set_config({key => $cache_key, data => $result});
    }
    return $result;
  }
  else {
    return {};
  }
}

1;

__END__

=head1 NAME

Bugzilla::WebService::Bugzilla - Global functions for the webservice interface.

=head1 DESCRIPTION

This provides functions that tell you about Bugzilla in general.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

Although the data input and output is the same for JSON-RPC, XML-RPC and REST,
the directions for how to access the data via REST is noted in each method
where applicable.

=head2 version

B<STABLE>

=over

=item B<Description>

Returns the current version of Bugzilla.

=item B<REST>

GET /version

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<version>, that is the version as a
string.

=item B<Errors> (none)

=item B<History>

=over

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 extensions

B<EXPERIMENTAL>

=over

=item B<Description>

Gets information about the extensions that are currently installed and enabled
in this Bugzilla.

=item B<REST>

GET /extensions

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<extensions>. This points to a hash. I<That> hash
contains the names of extensions as keys, and the values are a hash.
That hash contains a single key C<version>, which is the version of the
extension, or C<0> if the extension hasn't defined a version.

The return value looks something like this:

 extensions => {
     Example => {
         version => '3.6',
     },
     BmpConvert => {
         version => '1.0',
     },
 }

=item B<History>

=over

=item Added in Bugzilla B<3.2>.

=item As of Bugzilla B<3.6>, the names of extensions are canonical names
that the extensions define themselves. Before 3.6, the names of the
extensions depended on the directory they were in on the Bugzilla server.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 timezone

B<DEPRECATED> This method may be removed in a future version of Bugzilla.
Use L</time> instead.

=over

=item B<Description>

Returns the timezone that Bugzilla expects dates and times in.

=item B<REST>

GET /timezone

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<timezone>, that is the timezone offset as a
string in (+/-)XXXX (RFC 2822) format.

=item B<History>

=over

=item As of Bugzilla B<3.6>, the timezone returned is always C<+0000>
(the UTC timezone).

=item REST API call added in Bugzilla B<5.0>.

=back

=back


=head2 time

B<STABLE>

=over

=item B<Description>

Gets information about what time the Bugzilla server thinks it is, and
what timezone it's running in.

=item B<REST>

GET /time

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A struct with the following items:

=over

=item C<db_time>

C<dateTime> The current time in UTC, according to the Bugzilla
I<database server>.

Note that Bugzilla assumes that the database and the webserver are running
in the same time zone. However, if the web server and the database server
aren't synchronized for some reason, I<this> is the time that you should
rely on for doing searches and other input to the WebService.

=item C<web_time>

C<dateTime> This is the current time in UTC, according to Bugzilla's
I<web server>.

This might be different by a second from C<db_time> since this comes from
a different source. If it's any more different than a second, then there is
likely some problem with this Bugzilla instance. In this case you should
rely on the C<db_time>, not the C<web_time>.

=item C<web_time_utc>

Identical to C<web_time>. (Exists only for backwards-compatibility with
versions of Bugzilla before 3.6.)

=item C<tz_name>

C<string> The literal string C<UTC>. (Exists only for backwards-compatibility
with versions of Bugzilla before 3.6.)

=item C<tz_short_name>

C<string> The literal string C<UTC>. (Exists only for backwards-compatibility
with versions of Bugzilla before 3.6.)

=item C<tz_offset>

C<string> The literal string C<+0000>. (Exists only for backwards-compatibility
with versions of Bugzilla before 3.6.)

=back

=item B<History>

=over

=item Added in Bugzilla B<3.4>.

=item As of Bugzilla B<3.6>, this method returns all data as though the server
were in the UTC timezone, instead of returning information in the server's
local timezone.

=item REST API call added in Bugzilla B<5.0>.

=back

=back
