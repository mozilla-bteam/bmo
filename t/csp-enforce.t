#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Pins which pages serve CSP in enforcing mode and which stay report-only
# during the enforcement rollout.
#
# The rule lives in the content_security_policy helper (Bugzilla::App::Plugin::
# Glue): native Mojo routes enforce, legacy CGI scripts are report-only unless
# listed in CSP_ENFORCE_CGI, and any caller can force enforcement by passing
# report_only => 0. The only observable difference is the response header name,
# so that is what is asserted here.
#
# The case that most needs pinning is show_bug.cgi: only format=modal was
# enforcing before the rollout, and the allowlist is keyed on the script rather
# than the format, so enforcement there rests entirely on the explicit
# report_only => 0 in show_bug.cgi's modal branch. Dropping that argument would
# silently downgrade the most-trafficked page in BMO to report-only.

use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE} = 'log4perl-t.conf';

  # The Hostage plugin requires specific Host: headers; disable for tests.
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bmo.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;

use Bugzilla::Constants;

use Mojo::Transaction::HTTP;
use Test2::V0;
use Test2::Tools::Mock qw(mock);
use Test::Mojo;

use constant ENFORCE     => 'Content-Security-Policy';
use constant REPORT_ONLY => 'Content-Security-Policy-Report-Only';

my $t = Test::Mojo->new('Bugzilla::App');

# Ask the helper directly rather than round-tripping a request: the four cases
# differ only in the controller class and the stashed action name, both of which
# are cheaper to set up here than to reach through routing.
sub header_name_for {
  my (%opt) = @_;
  my $class
    = $opt{cgi} ? 'Bugzilla::App::Controller::CGI' : 'Mojolicious::Controller';
  my $c = $class->new(app => $t->app, tx => Mojo::Transaction::HTTP->new);
  $c->stash(action => $opt{action}) if defined $opt{action};
  return $c->content_security_policy(%{$opt{params} // {}})->header_name;
}

# A legacy CGI script that has not been cleaned up stays report-only.
is(header_name_for(cgi => 1, action => 'quips_cgi'),
  REPORT_ONLY, 'un-allowlisted CGI script is report-only');

# Native Mojo routes have always enforced and must continue to.
is(header_name_for(), ENFORCE, 'native Mojo route enforces');

# Allowlisting a script flips it to enforcing. CSP_ENFORCE_CGI is deliberately
# empty for now, so mock it -- and mock it in Glue rather than in
# Bugzilla::Constants, because Constants exports the sub and the helper calls
# the copy imported into Glue's symbol table.
{
  my $mock = mock 'Bugzilla::App::Plugin::Glue' =>
    (override => [CSP_ENFORCE_CGI => sub { {quips_cgi => 1} }]);
  is(header_name_for(cgi => 1, action => 'quips_cgi'),
    ENFORCE, 'allowlisted CGI script enforces');
}

# show_bug.cgi is not in the allowlist, so every format except modal (which
# passes report_only => 0 explicitly) must stay report-only. format=multiple
# renders bug/show-multiple.html.tmpl, which still carries inline event
# handlers, so enforcing there would break comment collapse/reply.
is(header_name_for(cgi => 1, action => 'show_bug_cgi'),
  REPORT_ONLY, 'show_bug.cgi is report-only by default');

is(
  header_name_for(
    cgi    => 1,
    action => 'show_bug_cgi',
    params => {SHOW_BUG_MODAL_CSP(1), report_only => 0}
  ),
  ENFORCE,
  'report_only => 0 forces enforcement despite the allowlist'
);

# Report-only pages must actually collect: the report_uri added to DEFAULT_CSP
# is what makes the soak useful.
{
  my $c = Bugzilla::App::Controller::CGI->new(
    app => $t->app,
    tx  => Mojo::Transaction::HTTP->new
  );
  $c->stash(action => 'quips_cgi');
  like(
    $c->content_security_policy->value,
    qr{report-uri /csp_report},
    'report-only pages point at the collector'
  );
}

# One of each end to end, so the header name really reaches the response rather
# than just the helper's return value: index.cgi for the report-only CGI surface
# and the report collector for a native Mojo route.
#
# show_bug.cgi?format=modal is deliberately not requested here. Rendering it
# would need a full bug fixture, and any error while rendering a CGI page takes
# the whole test process down with it -- Bugzilla::Error calls a bare exit
# (Bugzilla/Error.pm:152) that CGI::Compile's override does not reach. Its
# enforcing mode is pinned above at the helper level instead.
$t->get_ok('/home')->header_exists(REPORT_ONLY)->header_exists_not(ENFORCE);

$t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, '{}')
  ->status_is(204)->header_exists(ENFORCE)->header_exists_not(REPORT_ONLY);

done_testing;
