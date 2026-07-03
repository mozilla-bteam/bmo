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
  GITHUB_CACHE_SECONDS
  GITHUB_ERROR_CACHE_SECONDS
  GITHUB_MAX_PULL_REQUESTS
  GITHUB_REVIEWS_PER_PAGE
);

# Attachment content type used to mark a GitHub pull request link.
use constant GITHUB_CONTENT_TYPE => 'text/x-github-pull-request';

# Matches a GitHub PR URL, capturing (owner, repo, pr_number).
# The owner and repo are restricted to the character set GitHub actually
# permits (alphanumerics plus '.', '_' and '-'). This is deliberately strict:
# the URL comes from attachment data, which any user who can attach to a bug
# controls, so a permissive pattern would let characters like '?', '#' or '%'
# through and inject query strings or extra path segments into the requests we
# make to GitHub. It also keeps the values safe to echo back in API responses.
use constant GITHUB_PR_REGEX =>
  qr{^https://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/pull/(\d+)/?$};

use constant GITHUB_API_BASE    => 'https://api.github.com';
use constant GITHUB_API_TIMEOUT => 10;

# How long (in seconds) to cache a PR's summary in memcached. GitHub's
# unauthenticated rate limit is low (60 req/hr per IP) and authenticated is
# 5000/hr, so caching avoids re-fetching the same PR on every bug view.
use constant GITHUB_CACHE_SECONDS => 300;

# Cache inaccessible/failed lookups for a shorter period so that persistent
# failures (rate limiting, outages, private repos) don't re-hit GitHub on every
# bug view, while still recovering quickly once the PR becomes reachable again.
use constant GITHUB_ERROR_CACHE_SECONDS => 60;

# Upper bound on how many pull requests we will fetch for a single bug. Each
# uncached PR triggers outbound calls to GitHub, and PR attachments are
# user-supplied, so this caps the worst-case work (and outbound traffic) a
# single API request can generate. Real bugs rarely link this many PRs.
use constant GITHUB_MAX_PULL_REQUESTS => 50;

# Page size requested for a PR's reviews. GitHub returns reviews oldest-first
# and defaults to 30 per page, so on a busy PR the first page would be the
# *oldest* reviews - the wrong subset for computing each reviewer's latest
# state. Requesting GitHub's maximum (100) in a single call gives the correct
# result for effectively every PR while keeping this to one bounded request.
# A PR with more than 100 review events (extremely rare) could still report a
# stale reviewer state; we accept that rather than paginate unboundedly.
use constant GITHUB_REVIEWS_PER_PAGE => 100;

1;
