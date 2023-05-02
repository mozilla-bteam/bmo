# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Constants;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
  PHAB_AUTOMATION_USER
  PHAB_ATTACHMENT_PATTERN
  PHAB_CONTENT_TYPE
  PHAB_FEED_POLL_SECONDS
  PHAB_USER_POLL_SECONDS
  PHAB_GROUP_POLL_SECONDS
  PHAB_TIMEOUT
 
  LANDO_AUTOMATION_USER
  LANDO_BUG_UPDATE_FIELDS
 
  PULSEBOT_AUTOMATION_USER
  PULSEBOT_UPLIFT_REPOS
  PULSEBOT_BUG_UPDATE_FIELDS
);

use constant PHAB_ATTACHMENT_PATTERN => qr/^phabricator-D(\d+)/;
use constant PHAB_AUTOMATION_USER    => 'phab-bot@bmo.tld';
use constant PHAB_CONTENT_TYPE       => 'text/x-phabricator-request';
use constant PHAB_FEED_POLL_SECONDS  => $ENV{PHAB_FEED_POLL} // 5;
use constant PHAB_USER_POLL_SECONDS  => $ENV{PHAB_USER_POLL} // 60;
use constant PHAB_GROUP_POLL_SECONDS => $ENV{PHAB_GROUP_POLL} // 300;
use constant PHAB_TIMEOUT            => $ENV{PHAB_TIMEOUT} // 60;

use constant LANDO_AUTOMATION_USER   => 'lobot@bmo.tld';
use constant LANDO_BUG_UPDATE_FIELDS => qw(
  cf_status_firefox
  status_whiteboard
);

use constant PULSEBOT_AUTOMATION_USER   => 'pulsebot@bmo.tld';
use constant PULSEBOT_BUG_UPDATE_FIELDS => qw(
  bug_status
  comment
  comment_tags
  keywords
  resolution
);

1;
