# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);
use Test::More;

use Bugzilla;
BEGIN { Bugzilla->extensions }

use_ok('Bugzilla::WebService::Util', qw(fix_credentials));

{
  package MockCGI;

  sub new {
    my ($class, %headers) = @_;
    return bless {headers => \%headers}, $class;
  }

  sub http {
    my ($self, $field) = @_;
    return $self->{headers}{$field} // '';
  }
}

# CGI normalizes HTTP headers to uppercase with underscores (HTTP_X_BUGZILLA_FOO).
# The X_ prefix is stripped by $cgi->http(), so keys match API_AUTH_HEADERS constants
# e.g. X_BUGZILLA_API_KEY, X_BUGZILLA_LOGIN, X_BUGZILLA_PASSWORD, X_BUGZILLA_TOKEN.

# Headers only — no body params
{
  my $cgi    = MockCGI->new(X_BUGZILLA_API_KEY => 'header-key');
  my $params = {};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_api_key}, 'header-key', 'api_key from header');
}

# Body only — no headers
{
  my $cgi    = MockCGI->new();
  my $params = {api_key => 'body-key'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_api_key}, 'body-key', 'api_key from body when no header');
}

# Regression: Bug 2035598 — header must win over conflicting body api_key
{
  my $cgi    = MockCGI->new(X_BUGZILLA_API_KEY => 'header-key');
  my $params = {api_key => 'body-key'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_api_key}, 'header-key',
    'header api_key wins over body api_key');
  ok(!exists $params->{api_key}, 'body api_key param cleaned up');
}

# Regression: Bug 2035598 — header login/password wins over body login/password
{
  my $cgi = MockCGI->new(
    X_BUGZILLA_LOGIN    => 'header-user',
    X_BUGZILLA_PASSWORD => 'header-pass',
  );
  my $params = {login => 'body-user', password => 'body-pass'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_login},    'header-user', 'header login wins over body login');
  is($params->{Bugzilla_password}, 'header-pass', 'header password wins over body password');
}

# Regression: Bug 2035598 — header token wins over body token
{
  my $cgi    = MockCGI->new(X_BUGZILLA_TOKEN => 'header-token');
  my $params = {token => 'body-token'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_token}, 'header-token', 'header token wins over body token');
}

# Regression: Bug 2035598 — header wins over long-form body Bugzilla_api_key
# (the original fix removed the exists $params->{Bugzilla_api_key} guard from
# the header-processing loop; this locks down that behaviour)
{
  my $cgi    = MockCGI->new(X_BUGZILLA_API_KEY => 'header-key');
  my $params = {Bugzilla_api_key => 'body-key'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_api_key}, 'header-key',
    'header api_key wins over long-form body Bugzilla_api_key');
}

# Body login/password used when no auth headers present
{
  my $cgi    = MockCGI->new();
  my $params = {login => 'body-user', password => 'body-pass'};
  fix_credentials($params, $cgi);
  is($params->{Bugzilla_login},    'body-user', 'body login used when no header');
  is($params->{Bugzilla_password}, 'body-pass', 'body password used when no header');
}

done_testing;
