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
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Logging;

use MIME::Base64 qw(encode_base64);
use QA::Util qw(get_config generate_payload_signature);
use Test::Mojo;
use Test::More;

my $config  = get_config();
my $api_key = $config->{admin_user_api_key};
my $url     = Bugzilla->localconfig->urlbase;
my $secret  = $config->{github_automation_user_api_key};

my $t = Test::Mojo->new();

# Create a new test bug to link pull requests to.
my $new_bug = {
  product     => 'Firefox',
  component   => 'General',
  summary     => 'Test GitHub PR Status',
  type        => 'defect',
  version     => 'unspecified',
  severity    => 'blocker',
  description => 'This is a new test bug',
};

$t->post_ok(
  $url . 'rest/bug' => {'X-Bugzilla-API-Key' => $api_key} => json => $new_bug)
  ->status_is(200)->json_has('/id');

my $bug_id = $t->tx->res->json->{id};

# Attach two GitHub pull requests to the bug via the pull_request webhook.
# The endpoint under test reads the PR summary from memcached before it would
# ever contact GitHub, so we can seed the cache below with mock data and never
# make a real network request.
my @pr_urls = (
  'https://github.com/mozilla-bteam/bmo/pull/501',
  'https://github.com/mozilla-bteam/bmo/pull/502',
);

my $pr_number = 501;
foreach my $pr_url (@pr_urls) {
  my $payload = {
    action       => 'opened',
    pull_request => {
      html_url => $pr_url,
      title    => "Bug $bug_id - Test GitHub PR Status",
      number   => $pr_number,
    },
    repository => {full_name => 'mozilla-bteam/bmo'},
  };
  $t->post_ok(
    $url
      . 'rest/github/pull_request' => {
      'X-Hub-Signature-256' => generate_payload_signature($secret, $payload),
      'X-GitHub-Event'      => 'pull_request'
      } => json => $payload
  )->status_is(200)->json_has('/id');
  $pr_number++;
}

# Seed memcached with mock pull request data keyed by the PR URL. This is the
# exact structure _fetch_pull_request() would build after querying GitHub, so
# the live endpoint returns it verbatim without any outbound HTTP.
my %mock_prs = (
  $pr_urls[0] => {
    url          => $pr_urls[0],
    number       => 501,
    repo         => 'mozilla-bteam/bmo',
    sortkey      => 501,
    title        => 'Add a shiny new feature',
    state        => 'open',
    author       => 'octocat',
    reviews      => [{user => 'reviewer1', state => 'APPROVED'}],
    labels       => ['enhancement'],
    inaccessible => 0,
  },
  $pr_urls[1] => {
    url          => $pr_urls[1],
    number       => 502,
    repo         => 'mozilla-bteam/bmo',
    sortkey      => 502,
    title        => 'Fix an important bug',
    state        => 'merged',
    author       => 'hubot',
    reviews      => [],
    labels       => [],
    inaccessible => 0,
  },
);

foreach my $pr_url (keys %mock_prs) {
  Bugzilla->memcached->set_data({
    key        => "github_pr.$pr_url",
    value      => $mock_prs{$pr_url},
    expires_in => 300,
  });
}

# Requesting without an API key requires login and is rejected.
$t->get_ok($url . "rest/githubpr/bug_pull_requests/$bug_id")->status_is(401);

# Fetch the mocked pull request status for the bug.
$t->get_ok($url
    . "rest/githubpr/bug_pull_requests/$bug_id" =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200)
  ->json_has('/pull_requests')
  ->json_is('/pull_requests/0/url', $pr_urls[0])
  ->json_is('/pull_requests/0/number', 501)
  ->json_is('/pull_requests/0/repo', 'mozilla-bteam/bmo')
  ->json_is('/pull_requests/0/title', 'Add a shiny new feature')
  ->json_is('/pull_requests/0/state', 'open')
  ->json_is('/pull_requests/0/author', 'octocat')
  ->json_is('/pull_requests/0/reviews/0/user', 'reviewer1')
  ->json_is('/pull_requests/0/reviews/0/state', 'APPROVED')
  ->json_is('/pull_requests/0/labels/0', 'enhancement')
  ->json_is('/pull_requests/0/inaccessible', 0)
  ->json_is('/pull_requests/1/url', $pr_urls[1])
  ->json_is('/pull_requests/1/number', 502)
  ->json_is('/pull_requests/1/title', 'Fix an important bug')
  ->json_is('/pull_requests/1/state', 'merged')
  ->json_is('/pull_requests/1/author', 'hubot');

# Verify exactly two pull requests were returned.
my $result = $t->tx->res->json;
is(scalar @{$result->{pull_requests}}, 2, 'Two pull requests returned');

# Attach a GitHub PR URL containing characters that are not valid in a GitHub
# owner/repo (here a '?' that would otherwise inject a query string into the
# request we make to GitHub). The endpoint must refuse to parse it, skip it
# entirely, and never attempt an outbound fetch - so it should not appear in
# the results and the count must remain unchanged. We deliberately do NOT seed
# memcached for it: if the parsing were ever loosened, the endpoint would try a
# live fetch and the URL would leak into the response, failing this test.
my $malicious_url = 'https://github.com/octocat?evil=1/repo/pull/9999';
my $malicious_attachment = {
  summary      => 'Malicious PR URL',
  content_type => 'text/x-github-pull-request',
  data         => encode_base64($malicious_url),
  file_name    => 'github-malicious-9999-url.txt',
};
$t->post_ok(
  $url . "rest/bug/$bug_id/attachment" =>
    {'X-Bugzilla-API-Key' => $api_key} => json => $malicious_attachment)
  ->status_is(201)->json_has('/attachments');

$t->get_ok($url
    . "rest/githubpr/bug_pull_requests/$bug_id" =>
    {'X-Bugzilla-API-Key' => $api_key})->status_is(200);

my $after = $t->tx->res->json;
is(scalar @{$after->{pull_requests}}, 2,
  'Malformed PR URL is skipped, count unchanged');
ok(
  !(grep { ($_->{url} // '') =~ /octocat/ } @{$after->{pull_requests}}),
  'Malformed PR URL is not present in the results'
);

done_testing();
