# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubPullRequests::Constants;

use 5.10.1;
use strict;
use warnings;

use base 'Exporter';

our @EXPORT = qw(
  GITHUB_CONTENT_TYPE
  GITHUB_PR_REGEX
  GITHUB_API_BASE
  GITHUB_API_TIMEOUT
  GITHUB_REQUEST_BUDGET
  GITHUB_LOCK_SECONDS
  GITHUB_CACHE_SECONDS
  GITHUB_ERROR_CACHE_SECONDS
);

# Attachment content type used to mark a GitHub pull request link.
use constant GITHUB_CONTENT_TYPE => 'text/x-github-pull-request';

# Matches a GitHub PR URL, capturing (owner, repo, pr_number).
use constant GITHUB_PR_REGEX => qr{^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)/?$};

use constant GITHUB_API_BASE => 'https://api.github.com';

# Per-call timeout for a single GitHub API request.
use constant GITHUB_API_TIMEOUT => 5;

# Overall wall-clock budget (in seconds) for synchronously fetching PRs in a
# single request. Once exceeded we stop hitting GitHub and return the remaining
# PRs as "pending" rather than tying up the web worker. This is a soft limit:
# an in-progress PR may overrun it by up to GITHUB_API_TIMEOUT per call. The
# cache warms progressively across reloads as earlier PRs become cache hits.
use constant GITHUB_REQUEST_BUDGET => 15;

# TTL of the per-PR in-flight lock. While one request is fetching a PR, other
# concurrent requests skip it (returning "pending") instead of stampeding
# GitHub with duplicate calls. The lock expires on its own; on success the
# result is cached so later requests are served from cache regardless.
use constant GITHUB_LOCK_SECONDS => 15;

# How long (in seconds) to cache a PR's summary in memcached. GitHub's
# unauthenticated rate limit is low (60 req/hr per IP) and authenticated is
# 5000/hr, so caching avoids re-fetching the same PR on every bug view.
use constant GITHUB_CACHE_SECONDS => 300;

# Cache inaccessible/failed lookups for a shorter period so that persistent
# failures (rate limiting, outages, private repos) don't re-hit GitHub on every
# bug view, while still recovering quickly once the PR becomes reachable again.
use constant GITHUB_ERROR_CACHE_SECONDS => 60;

1;
