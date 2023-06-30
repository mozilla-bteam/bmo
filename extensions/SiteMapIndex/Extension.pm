# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::SiteMapIndex;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::SiteMapIndex::Util qw(bug_is_ok_to_index);

our $VERSION = '2.0';

#########
# Pages #
#########

sub template_before_process {
  my ($self, $args) = @_;
  my ($vars, $file) = @$args{qw(vars file)};

  return if $file ne 'global/header.html.tmpl';
  return unless (exists $vars->{bug} || exists $vars->{bugs});
  my $bugs = exists $vars->{bugs} ? $vars->{bugs} : [$vars->{bug}];
  return if ref $bugs ne 'ARRAY';

  foreach my $bug (@$bugs) {
    if (!bug_is_ok_to_index($bug)) {
      $vars->{sitemap_noindex} = 1;
      last;
    }
  }
}

#################
# Configuration #
#################

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{SiteMapIndex} = "Bugzilla::Extension::SiteMapIndex::Config";
}

sub before_robots_txt {
  my ($self, $args) = @_;

  return if !Bugzilla->params->{sitemapindex_enabled};

  my $sitemap_url
      = 'https://s3.us-west-2.amazonaws.com/'
      . Bugzilla->params->{sitemapindex_s3_bucket}
    . '/sitemap_index.xml';
  $args->{vars}{SITEMAP_URL} = $sitemap_url;
}

__PACKAGE__->NAME;
