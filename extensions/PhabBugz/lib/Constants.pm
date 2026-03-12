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

  UPLIFT_QUESTIONS
  UPLIFT_QE_TEST_LABEL

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

# Uplift request form questions in the order they should appear in markdown
# comments. Each entry's `keys` list contains all known Phabricator form
# strings (past and present) that map to that question. When the form schema
# changes, add the new string to `keys` and optionally update `label`.
use constant UPLIFT_QUESTIONS => [
  {
    keys  => ["User impact if declined/Reason for urgency", "User impact if declined"],
    label => "User impact if declined/Reason for urgency",
  },
  {
    keys  => ["Code covered by automated testing?", "Code covered by automated testing"],
    label => "Code covered by automated testing?",
  },
  {
    keys  => ["Fix verified in Nightly?", "Fix verified in Nightly"],
    label => "Fix verified in Nightly?",
  },
  {
    keys  => ["Needs manual QE testing?", "Needs manual QE test"],
    label => "Needs manual QE testing?",
  },
  {
    keys  => ["Steps to reproduce for manual QE testing"],
    label => "Steps to reproduce for manual QE testing",
  },
  {
    keys  => ["Risk associated with taking this patch"],
    label => "Risk associated with taking this patch",
  },
  {
    keys  => ["Explanation of risk level"],
    label => "Explanation of risk level",
  },
  {
    keys  => ["String changes made/needed?", "String changes made/needed"],
    label => "String changes made/needed?",
  },
  {
    keys  => ["Is Android affected?"],
    label => "Is Android affected?",
  },
];

# Label of the `UPLIFT_QUESTIONS` entry used to determine if manual QE testing is needed.
use constant UPLIFT_QE_TEST_LABEL => "Needs manual QE testing?";

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
