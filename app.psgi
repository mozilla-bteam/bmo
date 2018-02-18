#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

BEGIN { $main::BUGZILLA_PERSISTENT = 1 }

use File::Basename;
use File::Spec;

BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs( dirname(__FILE__) );
    lib->import(
        $dir,
        File::Spec->catdir( $dir, 'lib' ),
        File::Spec->catdir( $dir, qw(local lib perl5) )
    );

    # disable "use lib" from now on
    no warnings qw(redefine);
    *lib::import = sub { };
}

# This loads most of our modules.
use Bugzilla::Logging;
use Bugzilla ();
use Bugzilla::Constants ();
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::PSGI qw(compile_cgi);
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Bugzilla::RNG ();

use Plack;
use Plack::Builder;
use Plack::App::URLMap;
use Plack::App::WrapCGI;
use Plack::Response;

use constant STATIC => qw(
    data/webdot
    docs
    extensions/[^/]+/web
    graphs
    images
    js
    skins
);

# Pre-load all extensions
Bugzilla::Extension->load_all();
Bugzilla->preload_features();

# Force instantiation of template so Bugzilla::Template::PreloadProvider can do its magic.
Bugzilla->template;

my $bugzilla_app = builder {
    my $static_paths = join( '|', STATIC );

    enable 'Log4perl', category => 'Plack';

    enable 'Static',
        path => sub { s{^/(?:static/v\d+\.\d+/)?($static_paths)/}{$1/}gs },
        root => Bugzilla::Constants::bz_locations->{cgi_path};

    my @scripts = glob('*.cgi');

    my %mount;

    foreach my $script (@scripts) {
        my $name = basename($script);
        $mount{$name} = compile_cgi($script);
    }

    Bugzilla::Hook::process('psgi_builder', { mount => \%mount });

    foreach my $name ( keys %mount ) {
        mount "/$name" => $mount{$name};
    }

    # so mount / => $app will make *all* files redirect to the index.
    # instead we use an inline middleware to rewrite / to /index.cgi
    enable sub {
        my $app = shift;
        return sub {
            my $env = shift;
            $env->{PATH_INFO} = '/index.cgi' if $env->{PATH_INFO} eq '/';
            return $app->($env);
        };
    };

    mount '/rest' => $mount{'rest.cgi'};

};

unless (caller) {
    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(@ARGV);
    $runner->run($bugzilla_app);
    exit 0;
}

return $bugzilla_app;
