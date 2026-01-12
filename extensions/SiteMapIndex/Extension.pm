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

  # We use urlbase instead of <bucket>.storage.googleapis.com since we have
  # a rewrite rule in the nginx config to redirect for us. This is
  # because the sitemap specification requires the sitemap hosts to
  # be ones we own locally and not external sites.
  # For example: https://bugzilla.mozilla.org/sitemap/sitemap_index.xml will be rewritten to
  # https://<bucket>.storage.googleapis.com/sitemap_index.xml
  # Also if the GCP bucket name ever changes, we need to update the nginx config at
  # https://github.com/mozilla/webservices-infra/blob/main/bugzilla/k8s/bugzilla/templates/nginx-configmap.yaml
  # in addition to Bugzilla params.
  my $sitemap_url = Bugzilla->localconfig->urlbase . 'sitemap/sitemap_index.xml';
  $args->{vars}{SITEMAP_URL} = $sitemap_url;
}

__PACKAGE__->NAME;
