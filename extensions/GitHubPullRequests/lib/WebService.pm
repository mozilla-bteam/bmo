# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubPullRequests::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::WebService::Constants;
use Types::Standard qw(-types);
use Type::Params qw(compile);

use JSON qw(decode_json);
use LWP::UserAgent;

use constant GITHUB_CONTENT_TYPE  => 'text/x-github-pull-request';
use constant GITHUB_PR_REGEX      => qr{^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)/?$};
use constant GITHUB_API_BASE      => 'https://api.github.com';
use constant GITHUB_API_TIMEOUT   => 10;

# How long (in seconds) to cache a PR's summary in memcached. GitHub's
# unauthenticated rate limit is low (60 req/hr per IP) and authenticated is
# 5000/hr, so caching avoids re-fetching the same PR on every bug view.
use constant GITHUB_CACHE_SECONDS => 300;

use constant READ_ONLY => qw(
  bug_pull_requests
);

use constant PUBLIC_METHODS => qw(
  bug_pull_requests
);

sub bug_pull_requests {
  state $check = compile(Object, Dict [bug_id => Int]);
  my ($self, $params) = $check->(@_);

  my $user = Bugzilla->login(LOGIN_REQUIRED);

  ThrowUserError('invalid_parameter', {name => 'bug_id', err => 'required'})
    unless $params->{bug_id};

  my $bug = Bugzilla::Bug->check({id => $params->{bug_id}, cache => 1});

  my $ua = LWP::UserAgent->new(timeout => GITHUB_API_TIMEOUT);
  $ua->agent('BMO-Bugzilla/1.0');
  if (Bugzilla->params->{proxy_url}) {
    $ua->proxy('https', Bugzilla->params->{proxy_url});
  }

  # Authenticate when a token is configured. This raises GitHub's API rate
  # limit from 60 to 5000 requests/hour, avoiding HTTP 403 failures under load.
  my $token = Bugzilla->params->{github_api_token};
  if ($token) {
    $ua->default_header('Authorization' => "Bearer $token");
  }

  my @pull_requests;
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->contenttype ne GITHUB_CONTENT_TYPE;
    next if $attachment->isobsolete;

    # Don't expose private attachments (and their PR details) to users who
    # aren't permitted to see them.
    next if $attachment->isprivate && !$user->is_insider;

    my $url = $attachment->data;
    $url =~ s/\s+$//;

    my ($owner, $repo, $pr_number) = ($url =~ GITHUB_PR_REGEX);
    unless ($owner && $repo && $pr_number) {
      WARN("GitHub: could not parse PR URL: $url");
      next;
    }

    my $pr_data = _fetch_pull_request($ua, $owner, $repo, $pr_number);
    push @pull_requests, $pr_data;
  }

  return {pull_requests => \@pull_requests};
}

sub _fetch_pull_request {
  my ($ua, $owner, $repo, $pr_number) = @_;

  my $url     = "https://github.com/$owner/$repo/pull/$pr_number";
  my $api_url = GITHUB_API_BASE . "/repos/$owner/$repo/pulls/$pr_number";

  my $base = {
    url       => $url,
    number    => int($pr_number),
    repo      => "$owner/$repo",
    sortkey   => int($pr_number),
  };

  # Return a cached summary if we have a fresh one.
  my $cache_key = "github_pr." . $url;
  my $cached = Bugzilla->memcached->get_data({key => $cache_key});
  return $cached if defined $cached;

  my $pr_response = _github_get($ua, $api_url);
  unless ($pr_response->{ok}) {
    WARN("GitHub: failed to fetch PR $url: " . $pr_response->{errmsg});
    return {%$base, inaccessible => 1};
  }

  my $pr = $pr_response->{data};

  # GitHub should return a JSON object; anything else (an error object, a
  # list, etc.) means we can't trust the structure, so fall back gracefully.
  unless (ref($pr) eq 'HASH') {
    WARN("GitHub: unexpected response shape for PR $url");
    return {%$base, inaccessible => 1};
  }

  my $state;
  if ($pr->{draft}) {
    $state = 'draft';
  }
  elsif ($pr->{merged_at}) {
    $state = 'merged';
  }
  elsif ($pr->{state} eq 'closed') {
    $state = 'closed';
  }
  else {
    $state = 'open';
  }

  my @labels = map { $_->{name} } @{$pr->{labels} // []};

  my $reviews_response = _github_get($ua, $api_url . '/reviews');
  my @reviews;
  if ($reviews_response->{ok}) {
    @reviews = _summarize_reviews($reviews_response->{data});
  }

  my $pr_data = {
    %$base,
    title        => $pr->{title},
    state        => $state,
    author       => ref($pr->{user}) eq 'HASH' ? $pr->{user}{login} : undef,
    reviews      => \@reviews,
    labels       => \@labels,
    inaccessible => 0,
  };

  Bugzilla->memcached->set_data(
    {key => $cache_key, value => $pr_data, expires_in => GITHUB_CACHE_SECONDS});

  return $pr_data;
}

sub _github_get {
  my ($ua, $url) = @_;

  my $response = $ua->get(
    $url,
    'Accept'               => 'application/vnd.github+json',
    'X-GitHub-Api-Version' => '2022-11-28',
  );

  unless ($response->is_success) {
    return {ok => 0, errmsg => $response->status_line};
  }

  my $data = eval { decode_json($response->decoded_content) };
  if ($@) {
    return {ok => 0, errmsg => "JSON parse error: $@"};
  }

  return {ok => 1, data => $data};
}

sub _summarize_reviews {
  my ($reviews) = @_;

  return () unless ref($reviews) eq 'ARRAY';

  # Keep only the latest review state per reviewer.
  # Reviews are returned in chronological order so we can just overwrite.
  my %latest;
  my @order;
  for my $review (@{$reviews}) {
    my $login = $review->{user}{login};
    my $state = $review->{state};

    # COMMENTED is not a conclusive review state; skip it
    next if $state eq 'COMMENTED';

    if (!exists $latest{$login}) {
      push @order, $login;
    }
    $latest{$login} = $state;
  }

  return map { {user => $_, state => $latest{$_}} } @order;
}

sub rest_resources {
  return [
    qr{^/githubpr/bug_pull_requests/(\d+)$},
    {
      GET => {
        method => 'bug_pull_requests',
        params => sub { return {bug_id => $_[0]} },
      },
    },
  ];
}

1;
