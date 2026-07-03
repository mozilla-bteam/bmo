# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubPullRequests::API::V1::PullRequests;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Extension::GitHubPullRequests::Constants;

use JSON qw(decode_json);
use LWP::UserAgent;
use URI::Escape qw(uri_escape);

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/githubpr/bug_pull_requests/:bug_id')
    ->to('GitHubPullRequests::API::V1::PullRequests#bug_pull_requests');
}

sub bug_pull_requests {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO_REST);

  my $user = $self->bugzilla->login(LOGIN_REQUIRED);
  $user->id || return $self->user_error('login_required');

  # Kill switch: when disabled, return nothing rather than querying GitHub.
  return $self->render(json => {pull_requests => []})
    unless Bugzilla->params->{github_pr_status_enabled};

  my $bug_id = $self->param('bug_id');
  return $self->user_error('invalid_parameter', {name => 'bug_id', err => 'required'})
    unless $bug_id;

  my $bug = Bugzilla::Bug->check({id => $bug_id, cache => 1});

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

    # Bound the amount of work a single request can trigger. Anyone who can
    # attach to a bug can add PR attachments, and each uncached PR makes two
    # outbound calls to GitHub, so an unbounded loop is an amplification/DoS
    # vector (and risks rate-limiting our API token). Stop once we hit the cap.
    if (@pull_requests >= GITHUB_MAX_PULL_REQUESTS) {
      WARN( "GitHub: bug "
          . $bug->id
          . " has more than "
          . GITHUB_MAX_PULL_REQUESTS
          . " PR attachments; not fetching the rest");
      last;
    }

    my $pr_data = _fetch_pull_request($ua, $owner, $repo, $pr_number);
    push @pull_requests, $pr_data;
  }

  return $self->render(json => {pull_requests => \@pull_requests});
}

sub _fetch_pull_request {
  my ($ua, $owner, $repo, $pr_number) = @_;

  # Percent-encode the path segments as defense in depth. GITHUB_PR_REGEX
  # already limits these to a URL-safe character set, but encoding guarantees
  # that any unexpected character is treated as literal path content and cannot
  # inject a query string, fragment, or additional path segments into the
  # requests we send to GitHub. $pr_number is digits-only so needs no encoding.
  my $enc_owner = uri_escape($owner);
  my $enc_repo  = uri_escape($repo);

  my $url     = "https://github.com/$enc_owner/$enc_repo/pull/$pr_number";
  my $api_url = GITHUB_API_BASE . "/repos/$enc_owner/$enc_repo/pulls/$pr_number";

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
    return _cache_inaccessible($cache_key, $base);
  }

  my $pr = $pr_response->{data};

  # GitHub should return a JSON object; anything else (an error object, a
  # list, etc.) means we can't trust the structure, so fall back gracefully.
  unless (ref($pr) eq 'HASH') {
    WARN("GitHub: unexpected response shape for PR $url");
    return _cache_inaccessible($cache_key, $base);
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

  my $reviews_response
    = _github_get($ua, $api_url . '/reviews?per_page=' . GITHUB_REVIEWS_PER_PAGE);
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

sub _cache_inaccessible {
  my ($cache_key, $base) = @_;

  my $error_data = {%$base, inaccessible => 1};
  Bugzilla->memcached->set_data({
    key        => $cache_key,
    value      => $error_data,
    expires_in => GITHUB_ERROR_CACHE_SECONDS,
  });

  return $error_data;
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
    next unless ref($review) eq 'HASH';

    # A review left by a since-deleted GitHub account comes back with a null
    # user, so guard before dereferencing rather than auto-vivifying/dying.
    next unless ref($review->{user}) eq 'HASH';

    my $login = $review->{user}{login};
    next unless defined $login;

    my $state = $review->{state} // '';

    # COMMENTED is not a conclusive review state; skip it
    next if $state eq 'COMMENTED';

    if (!exists $latest{$login}) {
      push @order, $login;
    }
    $latest{$login} = $state;
  }

  return map { {user => $_, state => $latest{$_}} } @order;
}

1;
