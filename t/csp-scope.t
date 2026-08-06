#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Pins which responses carry a Content-Security-Policy header at all, as
# opposed to t/csp-enforce.t which pins enforcing vs report-only for the ones
# that do.
#
# The header is added in one place, the after_dispatch hook in Bugzilla::App,
# and that hook runs for every response: native Mojo routes, legacy CGI
# scripts, static files and the REST API alike. Documents are gated in by
# content type (CSP_DOCUMENT_TYPES), because CSP only governs how a browser
# renders a document. A REST client applies no policy and sends no violation
# report, so a policy on a JSON response is read by nobody while still costing
# ~1KB per response plus the Bugzilla->user lookup and nonce that building the
# policy needs.
#
# Both halves matter. Dropping the gate silently re-adds CSP to every REST
# response; widening it (or having some future route answer HTML where it used
# to answer JSON) would put an enforcing policy on the API surface, since
# native routes enforce.

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

use Bugzilla::App ();
use Bugzilla::Constants;

use Mojo::Message::Response;
use Test2::V0;
use Test::Mojo;

use constant ENFORCE     => 'Content-Security-Policy';
use constant REPORT_ONLY => 'Content-Security-Policy-Report-Only';

my $t = Test::Mojo->new('Bugzilla::App');

sub has_no_csp {
  my ($tester, $name) = @_;
  $tester->header_exists_not(ENFORCE, "$name: no enforcing CSP")
    ->header_exists_not(REPORT_ONLY, "$name: no report-only CSP");
}

# The content-type predicate, direct. Cheaper than finding a real route for each
# case, and it documents which types were considered rather than which happened
# to be reachable.
sub is_document {
  my ($content_type, $status) = @_;
  my $res = Mojo::Message::Response->new(code => $status // 200);
  $res->headers->content_type($content_type) if defined $content_type;
  return Bugzilla::App::_response_is_document($res) ? 1 : 0;
}

# Every listed type must actually be treated as one, which is what ties the
# constant to the predicate: an entry carrying a parameter or odd casing would
# be dead weight in the list and silently never match. image/svg+xml is the
# entry worth noting -- SVG can carry script and attachment.cgi serves it
# inline, so it needs a policy even though it is not HTML.
ok(is_document($_), "$_ is a document") for CSP_DOCUMENT_TYPES;

# A content type arrives with parameters attached and in whatever case the CGI
# script or renderer used, so neither can be compared verbatim.
ok(is_document('text/html; charset=UTF-8'), 'parameters are ignored');
ok(is_document('TEXT/HTML'),                'comparison is case-insensitive');
ok(is_document(' text/html '),              'whitespace is ignored');

ok(!is_document('application/json'), 'json is not a document');
ok(!is_document('text/xml'),         'xml (xml.cgi) is not a document');
ok(!is_document('text/plain'),       'plain text is not a document');
ok(!is_document('application/octet-stream'), 'downloads are not documents');
ok(!is_document(undef), 'a response with no content type is not a document');

# Matching the type as a whole rather than by prefix or substring.
ok(!is_document('application/json+html'), 'a type ending in html misses');
ok(!is_document('text/htmlish'),          'a longer type misses');

# Content type alone is not enough: Mojo stamps text/html on a rendered response
# even when there is no body, so a bodiless status has to be excluded on status.
ok(!is_document('text/html', 204), 'a 204 is not a document');
ok(!is_document('text/html', 304), 'a 304 is not a document');

# End to end. A native /rest route: JSON, and the route that would otherwise
# enforce.
has_no_csp($t->get_ok('/rest/config/component_teams'), 'native REST route');

# The version endpoint is a static file served as JSON, so it exercises the
# static branch of dispatch rather than the renderer.
has_no_csp($t->get_ok('/__version__'), 'static JSON');

# The CSP collector itself. It renders data => '' with status 204, which Mojo
# labels text/html, so this is the case that the status check above catches.
has_no_csp(
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, '{}')
    ->status_is(204),
  'csp report collector'
);

# The gate must not have cost the HTML surface its policy -- that is the whole
# point of the report-only soak. index.cgi is the legacy CGI stack, whose
# headers reach the Mojo response by a different path (Bugzilla::CGI::header
# parses them in) than a rendered response.
$t->get_ok('/home')->header_exists(REPORT_ONLY)->header_exists_not(ENFORCE);
my $headers = $t->tx->res->headers;
like(
  $headers->header(REPORT_ONLY),
  qr{report-uri /csp_report},
  'the document policy still points at the collector'
);

done_testing;
