#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
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

use Log::Log4perl;
use Log::Log4perl::Layout::Mozilla;
use Log::Log4perl::Level;
use Mojo::JSON qw(decode_json encode_json);

use Test2::V0;
use Test::Mojo;

use Bugzilla::App::Controller::CSPReport;

# The test log config only emits at FATAL, so attach an in-memory appender to
# the controller's logger to capture the CSP-VIOLATION WARN lines it writes.
my $log_appender = Log::Log4perl::Appender->new(
  'Log::Log4perl::Appender::String', name => 'csp_report_test');
my $logger = Log::Log4perl->get_logger('Bugzilla::App::Controller::CSPReport');
$logger->add_appender($log_appender);
$logger->level($WARN);

# Keep test output clean: capture the WARN lines in our in-memory appender only
# and stop them propagating up to the root logger's Screen appender (which the
# conf/log4perl-t.conf config otherwise emits to stdout).
$logger->additivity(0);

sub last_log {
  my $out = $log_appender->string;
  $log_appender->string('');
  return $out;
}

my $t = Test::Mojo->new('Bugzilla::App');

# report-uri format: single violation wrapped in "csp-report".
{
  my $body = encode_json({
    'csp-report' => {
      'document-uri'      => 'http://bmo.test/show_bug.cgi?id=1',
      'violated-directive' => 'script-src',
      'blocked-uri'       => 'inline',
      'source-file'       => 'http://bmo.test/foo.js',
      'line-number'       => 42,
      'disposition'       => 'report',
    }
  });
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204)->content_is('');
  my $log = last_log();
  like($log, qr/CSP-VIOLATION/,                      'report-uri: tagged');
  like($log, qr{document=http://bmo\.test/show_bug\.cgi\b}, 'report-uri: document');
  like($log, qr/directive=script-src/,               'report-uri: directive');
  like($log, qr/blocked=inline/,                     'report-uri: blocked');
  like($log, qr{source=http://bmo\.test/foo\.js:42}, 'report-uri: source:line');

  # "report" vs "enforce" is what separates a violation we still have time to
  # fix from one that is already breaking a page.
  like($log, qr/disposition=report/, 'report-uri: disposition');
}

# The Reporting API ("report-to") batch format is deliberately not parsed: no
# Reporting-Endpoints header is ever sent, and an array body would let a single
# request emit an unbounded number of log lines. It must fall through to the
# raw-payload branch, logging exactly one line.
{
  my $body = encode_json([
    map { {type => 'csp-violation', body => {documentURL => "http://bmo.test/$_"}} }
      1 .. 3
  ]);
  $t->post_ok('/csp_report', {'Content-Type' => 'application/reports+json'}, $body)
    ->status_is(204);
  my $log = last_log();
  is(scalar(() = $log =~ /CSP-VIOLATION/g), 1, 'array body logs a single line');
  unlike($log, qr/document=/, 'array body not normalised as a violation');
}

# Query strings and fragments are stripped from reported URLs before logging:
# BMO puts one-time secrets in GET query strings (token.cgi?t=...) and CSP's
# report-stripping algorithm leaves them in place.
{
  my $body = encode_json({
    'csp-report' => {
      'document-uri'       => 'http://bmo.test/token.cgi?t=sekrit&a=cfmpw',
      'violated-directive' => 'script-src',
      'blocked-uri'        => 'http://bmo.test/x.cgi?api_key=sekrit2',
      'source-file'        => 'http://bmo.test/foo.js?v=1#sekrit3',
    }
  });
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  my $log = last_log();
  like($log,   qr{document=http://bmo\.test/token\.cgi\s}, 'document query stripped');
  like($log,   qr{blocked=http://bmo\.test/x\.cgi\s},      'blocked query stripped');
  like($log,   qr{source=http://bmo\.test/foo\.js:},       'source query/fragment stripped');
  unlike($log, qr/sekrit/, 'no query-string or fragment secret reaches the log');
}

# Unparseable body still returns 204 and logs a distinct line (no crash).
{
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'},
    'this is not json')->status_is(204);
  like(last_log(), qr/CSP-VIOLATION unparseable report:/, 'garbage: unparseable');
}

# Valid JSON of an unexpected shape falls back to logging the raw payload, with
# anything query-string-shaped redacted.
{
  my $body
    = encode_json({some => 'other-json', url => 'http://bmo.test/token.cgi?t=sekrit'});
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  my $log = last_log();
  like($log,   qr/CSP-VIOLATION/, 'unknown shape: tagged');
  like($log,   qr/other-json/,    'unknown shape: raw payload logged');
  unlike($log, qr/sekrit/,        'unknown shape: query string redacted');
}

# Oversized bodies are discarded before any JSON parsing is attempted.
{
  my $body = '{"csp-report":{"blocked-uri":"' . ('x' x (65 * 1024)) . '"}}';
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  my $log = last_log();
  like($log,   qr/CSP-VIOLATION oversized report discarded: \d+ bytes/,
    'oversized: discarded with size note');
  unlike($log, qr/blocked=/, 'oversized: body not parsed/logged');
}

# Untrusted values are sanitised in the log line: control characters (a
# multi-line log-injection vector) are replaced and over-long values truncated.
{
  my $long = 'x' x 600;
  my $body = encode_json({
    'csp-report' => {
      'document-uri'       => "http://bmo.test/a\nb",
      'violated-directive' => 'script-src',
      'blocked-uri'        => $long,
    }
  });
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  my $log = last_log();
  like($log, qr{document=http://bmo\.test/a%20b},
    'control chars replaced and encoded');
  unlike($log, qr/document=\S*\n/,       'no injected newline in log line');
  like($log,   qr/blocked=x{500}\.\.\./, 'long value truncated with ellipsis');
  unlike($log, qr/x{501}/,               'value does not exceed the cap');
}

# The log line is space-delimited key=value, and this endpoint is reachable by a
# plain cross-site form POST -- so a value containing a space or "=" must not be
# able to forge additional fields. Whatever is logged, each key appears exactly
# once and the forged text stays inside the value it was submitted in.
{
  my $body = encode_json({
    'csp-report' => {
      'document-uri' => 'http://bmo.test/x directive=forged blocked=forged',
      'violated-directive' => 'script-src=sneaky',
      'blocked-uri'        => 'a b=c',
    }
  });
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  my $log = last_log();
  is(scalar(() = $log =~ / directive=/g), 1, 'exactly one directive= field');
  is(scalar(() = $log =~ / blocked=/g),   1, 'exactly one blocked= field');
  unlike($log, qr/=forged/, 'forged delimiters encoded, not left as fields');
  like($log, qr{document=http://bmo\.test/x%20directive%3Dforged%20blocked%3Dforged},
    'spaces and equals percent-encoded within the value');
  like($log, qr/directive=script-src%3Dsneaky/, 'directive value encoded');
  like($log, qr/blocked=a%20b%3Dc/,             'blocked value encoded');
}

# The encoding must not mask itself: a literal "%" in a reported value is
# encoded first, so the log line can be decoded unambiguously.
{
  my $body = encode_json(
    {'csp-report' => {'blocked-uri' => '%20already', 'violated-directive' => 'img-src'}});
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  like(last_log(), qr/blocked=%2520already/, 'literal percent is escaped');
}

# Missing fields fall back to a dash rather than an empty value.
{
  my $body = encode_json({'csp-report' => {'violated-directive' => 'style-src'}});
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  like(last_log(),
    qr/document=- directive=style-src blocked=- source=-:- disposition=-/,
    'missing fields rendered as dashes');
}

# The report also goes out as MozLog "Fields", which is what lets the rollout
# inventory be aggregated with jq or the GCP logging console rather than by
# parsing the summary line. Only conf/log4perl-json.conf renders with this
# layout in production, so attach it here to see what that emits.
{
  my $mozlog = Log::Log4perl::Appender->new('Log::Log4perl::Appender::String',
    name => 'csp_report_mozlog');
  $mozlog->layout(Log::Log4perl::Layout::Mozilla->new({}));
  $logger->add_appender($mozlog);

  my $body = encode_json({
    'csp-report' => {
      'document-uri'       => 'http://bmo.test/enter_bug.cgi?product=Firefox',
      'violated-directive' => 'script-src',
      'blocked-uri'        => 'inline',
      'source-file'        => 'http://bmo.test/foo.js',
      'line-number'        => 42,
      'disposition'        => 'enforce',
    }
  });
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'}, $body)
    ->status_is(204);
  last_log();

  my $fields = decode_json($mozlog->string)->{Fields};
  is($fields->{csp_document}, 'http://bmo.test/enter_bug.cgi',
    'MozLog field: document, query stripped');
  is($fields->{csp_directive},   'script-src', 'MozLog field: directive');
  is($fields->{csp_blocked},     'inline',     'MozLog field: blocked');
  is($fields->{csp_disposition}, 'enforce',    'MozLog field: disposition');
  like($fields->{msg}, qr/CSP-VIOLATION/, 'MozLog message still carries the tag');

  # Fields live in the per-request MDC, which Bugzilla::cleanup clears. Without
  # that, a field from one report would reappear on later log lines -- including
  # lines from unrelated requests -- and quietly corrupt the inventory.
  $mozlog->string('');
  $t->post_ok('/csp_report', {'Content-Type' => 'application/csp-report'},
    encode_json({'csp-report' => {'violated-directive' => 'style-src'}}))
    ->status_is(204);
  last_log();

  my $next = decode_json($mozlog->string)->{Fields};
  is($next->{csp_directive}, 'style-src', 'MozLog field: second report logged');
  ok(!exists $next->{csp_disposition},
    'fields do not leak from the previous request');

  $logger->remove_appender('csp_report_mozlog');
}

# The per-IP rate is read from the rate_limit_rules param so it can be retuned
# from editparams.cgi instead of by deploying. Kept last: it mutates params.
{
  my $params = Bugzilla->params;

  $params->{rate_limit_rules} = encode_json({csp_report => [7, 30]});
  is(Bugzilla::App::Controller::CSPReport::_rate_limit(),
    [7, 30], 'rate comes from the rate_limit_rules param');

  # An install whose stored param predates the csp_report rule must not end up
  # with no limit at all -- this is a log-flood vector.
  $params->{rate_limit_rules} = encode_json({});
  is(Bugzilla::App::Controller::CSPReport::_rate_limit(),
    [100, 60], 'a missing rule falls back to the default');

  $params->{rate_limit_active} = 0;
  is(Bugzilla::App::Controller::CSPReport::_rate_limit(),
    undef, 'rate limiting honours the site-wide switch');
}

done_testing;
