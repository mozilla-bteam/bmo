# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubPullRequests;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Extension);

use Bugzilla;
use Bugzilla::Extension::GitHubPullRequests::Constants;

our $VERSION = '0.01';

sub template_before_process {
  my ($self, $args) = @_;
  my $file = $args->{'file'};
  my $vars = $args->{'vars'};

  return unless Bugzilla->params->{github_pr_status_enabled};
  return unless Bugzilla->user->id;
  return unless $file =~ /bug_modal\/(header|edit)\.html\.tmpl$/;

  my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
  return unless $bug;

  # Note: this only counts linked (non-obsolete) PR attachments. The actual
  # open/closed/merged state isn't known until the WebService queries GitHub,
  # so we can't report an "open" count at template-processing time.
  my $has_prs = 0;
  my $linked_pr_count = 0;
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->contenttype ne GITHUB_CONTENT_TYPE;
    next if $attachment->isobsolete;

    # Don't reveal that a private PR attachment exists to users who aren't
    # permitted to see it; the WebService applies the same check.
    next if $attachment->isprivate && !Bugzilla->user->is_insider;
    $has_prs = 1;
    $linked_pr_count++;
  }

  $vars->{github_pull_requests}      = $has_prs;
  $vars->{github_linked_pr_count}    = $linked_pr_count;
}

__PACKAGE__->NAME;
