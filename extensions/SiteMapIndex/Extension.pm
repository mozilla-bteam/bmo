# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Sitemap Bugzilla Extension.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>
#   Dave Lawrence <dkl@mozilla.com>

package Bugzilla::Extension::SiteMapIndex;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

our $VERSION = '1.0';

use Bugzilla::Constants qw(bz_locations ON_WINDOWS);
use Bugzilla::Util qw(get_text);
use Bugzilla::Install::Filesystem;

use Bugzilla::Extension::SiteMapIndex::Constants;
use Bugzilla::Extension::SiteMapIndex::Util;

use DateTime;
use IO::File;
use POSIX;

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

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{page_id};

    if ($page =~ m{^sitemap/sitemap\.}) {
        my $map = generate_sitemap(__PACKAGE__->NAME);
        print Bugzilla->cgi->header('text/xml');
        print $map;
        exit;
    }
}

################
# Installation #
################

sub install_before_final_checks {
    my ($self) = @_;
    if (!Bugzilla->localconfig->{urlbase}) {
        print STDERR get_text('sitemap_no_urlbase'), "\n";
        return;
    }
    if (Bugzilla->params->{'requirelogin'}) {
        print STDERR get_text('sitemap_requirelogin'), "\n";
        return;
    }

    return if (Bugzilla->localconfig->{urlbase} ne 'https://bugzilla.mozilla.org/');
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $create_dirs  = $args->{'create_dirs'};
    my $recurse_dirs = $args->{'recurse_dirs'};
    my $htaccess     = $args->{'htaccess'};

    # Create the sitemap directory to store the index and sitemap files
    my $sitemap_path = bz_locations->{'datadir'} . "/" . __PACKAGE__->NAME;

    $create_dirs->{$sitemap_path} = Bugzilla::Install::Filesystem::DIR_CGI_WRITE
                                    | Bugzilla::Install::Filesystem::DIR_ALSO_WS_SERVE;

    $recurse_dirs->{$sitemap_path} = {
        files => Bugzilla::Install::Filesystem::CGI_WRITE
                 | Bugzilla::Install::Filesystem::DIR_ALSO_WS_SERVE,
        dirs  => Bugzilla::Install::Filesystem::DIR_CGI_WRITE
                 | Bugzilla::Install::Filesystem::DIR_ALSO_WS_SERVE
    };

    # Create a htaccess file that allows the sitemap files to be served out
    $htaccess->{"$sitemap_path/.htaccess"} = {
        perms    => Bugzilla::Install::Filesystem::WS_SERVE,
        contents => <<EOT
# Allow access to sitemap files created by the SiteMapIndex extension
<FilesMatch ^sitemap.*\\.xml(.gz)?\$>
  Allow from all
</FilesMatch>
Deny from all
EOT
    };
}

sub before_robots_txt {
    my ($self, $args) = @_;
    $args->{vars}{SITEMAP_URL} = Bugzilla->localconfig->{urlbase} . SITEMAP_URL;
}

__PACKAGE__->NAME;
