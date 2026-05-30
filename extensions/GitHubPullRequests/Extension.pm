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

use constant GITHUB_CONTENT_TYPE => 'text/x-github-pull-request';

our $VERSION = '0.01';

sub template_before_process {
  my ($self, $args) = @_;
  my $file = $args->{'file'};
  my $vars = $args->{'vars'};

  return unless Bugzilla->user->id;
  return unless $file =~ /bug_modal\/(header|edit)\.html\.tmpl$/;

  my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
  return unless $bug;

  my $has_prs = 0;
  my $open_pr_count = 0;
  foreach my $attachment (@{$bug->attachments}) {
    next if $attachment->contenttype ne GITHUB_CONTENT_TYPE;
    next if $attachment->isobsolete;
    $has_prs = 1;
    $open_pr_count++;
  }

  $vars->{github_pull_requests}      = $has_prs;
  $vars->{github_open_pr_count}      = $open_pr_count;
}

sub webservice {
  my ($self, $args) = @_;
  $args->{dispatch}->{GitHubPullRequests}
    = 'Bugzilla::Extension::GitHubPullRequests::WebService';
}

__PACKAGE__->NAME;
