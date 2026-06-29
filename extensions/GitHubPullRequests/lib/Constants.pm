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
);

# Attachment content type used to mark a GitHub pull request link.
use constant GITHUB_CONTENT_TYPE => 'text/x-github-pull-request';

# Matches a GitHub PR URL, capturing (owner, repo, pr_number).
use constant GITHUB_PR_REGEX => qr{^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)/?$};

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

1;
