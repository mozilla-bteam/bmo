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

  my $reviews_url = $api_url . '/reviews?per_page=' . GITHUB_REVIEWS_PER_PAGE;

  # Look up the cached wrapper. A new key prefix (.v2.) is used so that any
  # pre-existing entries from the old bare-$pr_data format are ignored and
  # simply expire on their own - no migration or shape-sniffing needed.
  my $cache_key = "github_pr.v2." . $url;
  my $cached = Bugzilla->memcached->get_data({key => $cache_key});

  # Fresh hit: still inside the freshness window, so serve without any call.
  if (defined $cached && ref($cached) eq 'HASH') {
    return $cached->{pr_data}
      if defined $cached->{fresh_until} && time() < $cached->{fresh_until};
  }

  # Stale hit with etags: revalidate with conditional requests. 304 responses
  # are free (GitHub does not count them against the rate limit), so an
  # unchanged PR costs nothing beyond the round trip.
  if ( defined $cached
    && ref($cached) eq 'HASH'
    && ref($cached->{pr_data}) eq 'HASH'
    && ($cached->{pr_etag} || $cached->{reviews_etag}))
  {
    return _revalidate_pull_request($ua, $cache_key, $base, $api_url, $cached);
  }

  # Miss (or an entry without etags, e.g. a cached inaccessible result): do a
  # full fetch.
  my $pr_response = _github_get($ua, $api_url);
  unless ($pr_response->{ok}) {
    _warn_fetch_failure($url, $pr_response);
    return _cache_inaccessible($cache_key, $base);
  }

  my $pr = $pr_response->{data};

  # GitHub should return a JSON object; anything else (an error object, a
  # list, etc.) means we can't trust the structure, so fall back gracefully.
  unless (ref($pr) eq 'HASH') {
    WARN("GitHub: unexpected response shape for PR $url");
    return _cache_inaccessible($cache_key, $base);
  }

  my $reviews_response = _github_get($ua, $reviews_url);
  my @reviews;
  if ($reviews_response->{ok}) {
    @reviews = _summarize_reviews($reviews_response->{data});
  }
  else {
    _warn_fetch_failure("$url reviews", $reviews_response);
  }

  my $pr_data = {%$base, _pr_summary_fields($pr), reviews => \@reviews};

  _store_wrapper($cache_key, {
    pr_data      => $pr_data,
    pr_etag      => $pr_response->{etag},
    reviews_etag => $reviews_response->{ok} ? $reviews_response->{etag} : undef,
  });

  return $pr_data;
}

# Revalidate a stale-but-cached PR using conditional requests. On a 304 we
# reuse the cached fields; on a 200 we recompute from the fresh body. An error
# on the PR endpoint is fatal (falls back to inaccessible); a reviews error is
# non-fatal and yields empty reviews, matching the full-fetch path.
sub _revalidate_pull_request {
  my ($ua, $cache_key, $base, $api_url, $cached) = @_;

  my $reviews_url = $api_url . '/reviews?per_page=' . GITHUB_REVIEWS_PER_PAGE;
  my $old_data    = $cached->{pr_data};

  # PR endpoint.
  my $pr_response = _github_get($ua, $api_url, $cached->{pr_etag});
  unless ($pr_response->{ok}) {
    _warn_fetch_failure($old_data->{url}, $pr_response);
    return _cache_inaccessible($cache_key, $base);
  }

  my ($pr_fields, $pr_etag);
  if ($pr_response->{not_modified}) {

    # Unchanged: reuse cached base fields and keep the existing etag.
    $pr_fields = {
      title        => $old_data->{title},
      state        => $old_data->{state},
      author       => $old_data->{author},
      labels       => $old_data->{labels},
      inaccessible => 0,
    };
    $pr_etag = $cached->{pr_etag};
  }
  else {
    my $pr = $pr_response->{data};
    unless (ref($pr) eq 'HASH') {
      WARN("GitHub: unexpected response shape for PR " . $old_data->{url});
      return _cache_inaccessible($cache_key, $base);
    }
    $pr_fields = {_pr_summary_fields($pr)};
    $pr_etag   = $pr_response->{etag};
  }

  # Reviews endpoint.
  my $reviews_response = _github_get($ua, $reviews_url, $cached->{reviews_etag});
  my ($reviews, $reviews_etag);
  if (!$reviews_response->{ok}) {
    _warn_fetch_failure($old_data->{url} . ' reviews', $reviews_response);
    $reviews      = [];
    $reviews_etag = undef;
  }
  elsif ($reviews_response->{not_modified}) {
    $reviews      = $old_data->{reviews} // [];
    $reviews_etag = $cached->{reviews_etag};
  }
  else {
    $reviews      = [_summarize_reviews($reviews_response->{data})];
    $reviews_etag = $reviews_response->{etag};
  }

  my $pr_data = {%$base, %$pr_fields, reviews => $reviews};

  _store_wrapper($cache_key,
    {pr_data => $pr_data, pr_etag => $pr_etag, reviews_etag => $reviews_etag});

  return $pr_data;
}

# Derive the servable summary fields (title/state/author/labels) from a PR body.
sub _pr_summary_fields {
  my ($pr) = @_;

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

  return (
    title        => $pr->{title},
    state        => $state,
    author       => ref($pr->{user}) eq 'HASH' ? $pr->{user}{login} : undef,
    labels       => [map { $_->{name} } @{$pr->{labels} // []}],
    inaccessible => 0,
  );
}

# Store the versioned cache wrapper. The freshness window (GITHUB_CACHE_SECONDS)
# is tracked in-band via fresh_until, while the hard memcached TTL is the much
# longer GITHUB_REVALIDATE_SECONDS so the etags outlive the freshness window and
# remain available for conditional revalidation.
sub _store_wrapper {
  my ($cache_key, $wrapper) = @_;

  $wrapper->{fresh_until} = time() + GITHUB_CACHE_SECONDS;
  Bugzilla->memcached->set_data({
    key        => $cache_key,
    value      => $wrapper,
    expires_in => GITHUB_REVALIDATE_SECONDS,
  });
}

# Classify a fetch failure and log it distinctly so a globally-misconfigured
# token (401/403 across many repos) is unmistakable and doesn't look like an
# ordinary private/deleted PR (404).
sub _warn_fetch_failure {
  my ($what, $response) = @_;

  my $status = $response->{status} // 0;
  if ($status == 401 || $status == 403) {
    WARN("GitHub: auth/permission failure ($status) for $what"
        . " - check github_api_token scope/validity");
  }
  elsif ($status == 404) {
    WARN("GitHub: PR not found or private ($status): $what");
  }
  else {
    WARN("GitHub: failed to fetch $what: " . $response->{errmsg});
  }
}

sub _cache_inaccessible {
  my ($cache_key, $base) = @_;

  my $error_data = {%$base, inaccessible => 1};

  # Inaccessible entries carry no etags and use the shorter error TTL so we
  # recover quickly once the PR becomes reachable again.
  Bugzilla->memcached->set_data({
    key        => $cache_key,
    value      => {pr_data => $error_data, fresh_until => time() + GITHUB_ERROR_CACHE_SECONDS},
    expires_in => GITHUB_ERROR_CACHE_SECONDS,
  });

  return $error_data;
}

sub _github_get {
  my ($ua, $url, $etag) = @_;

  my @headers = (
    'Accept'               => 'application/vnd.github+json',
    'X-GitHub-Api-Version' => '2022-11-28',
  );
  push @headers, ('If-None-Match' => $etag) if defined $etag;

  my $response = $ua->get($url, @headers);

  # LWP treats 304 as non-success, but for a conditional request it means the
  # cached copy is still valid. GitHub echoes the ETag on a 304, so carry it
  # through to keep the stored value current.
  if ($response->code == 304) {
    return {
      ok           => 1,
      not_modified => 1,
      status       => 304,
      etag         => $response->header('ETag'),
    };
  }

  unless ($response->is_success) {
    return {ok => 0, status => $response->code, errmsg => $response->status_line};
  }

  my $data = eval { decode_json($response->decoded_content) };
  if ($@) {
    return {ok => 0, status => $response->code, errmsg => "JSON parse error: $@"};
  }

  return {
    ok           => 1,
    not_modified => 0,
    status       => $response->code,
    etag         => $response->header('ETag'),
    data         => $data,
  };
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
