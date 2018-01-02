# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl;

use 5.10.1;
use strict;
use warnings;

use File::Find ();
use Cwd ();
use Carp ();

use Bugzilla::ModPerl::BlockIP;
use Bugzilla::ModPerl::ResponseHandler;
use Bugzilla::ModPerl::CleanupHandler;
use Bugzilla::Constants qw(USE_NYTPROF);

use Apache2::Log ();
use Apache2::ServerUtil;
use Apache2::SizeLimit;
use ModPerl::RegistryLoader ();
use File::Basename ();
use File::Find ();

use Bugzilla ();
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Bugzilla::RNG ();

BEGIN {
    if (USE_NYTPROF) {
        $ENV{NYTPROF} = "savesrc=0:start=no:addpid=1";
    }
}
use if USE_NYTPROF, 'Devel::NYTProf::Apache';

# Make warnings go to the virtual host's log and not the main
# server log.
BEGIN { *CORE::GLOBAL::warn = \&Apache2::ServerRec::warn; }

sub startup {

    # Pre-compile the CGI.pm methods that we're going to use.
    Bugzilla::CGI->compile(qw(:cgi :push));

    # Pre-load localconfig. It might already be loaded, but we need to make sure.
    Bugzilla->localconfig;
    if ( $ENV{LOCALCONFIG_ENV} ) {
        delete @ENV{ (Bugzilla::Install::Localconfig::ENV_KEYS) };
    }

    # This means that every httpd child will die after processing a request if it
    # is taking up more than $apache_size_limit of RAM all by itself, not counting RAM it is
    # sharing with the other httpd processes.
    my $limit = Bugzilla->localconfig->{apache_size_limit};
    if ( $limit < 400_000 ) {
        $limit = 400_000;
    }
    Apache2::SizeLimit->set_max_unshared_size($limit);

    my $cgi_path = Bugzilla::Constants::bz_locations()->{'cgi_path'};

    # Set up the configuration for the web server
    my $server = Apache2::ServerUtil->server;
    my $conf   = Bugzilla::ModPerl->apache_config($cgi_path);
    $server->add_config( [ grep { length $_ } split( "\n", $conf ) ] );


    # Pre-load all extensions
    Bugzilla::Extension->load_all();

    Bugzilla->preload_features();

    # Force instantiation of template so Bugzilla::Template::PreloadProvider can do its magic.
    Bugzilla->template;

    Bugzilla::ModPerl::BlockIP->set_memcached( Bugzilla::Memcached->_new()->{memcached} );

    # Have ModPerl::RegistryLoader pre-compile all CGI scripts.
    my $rl = ModPerl::RegistryLoader->new( package => 'Bugzilla::ModPerl::ResponseHandler' );

    my $feature_files = Bugzilla::Install::Requirements::map_files_to_features();

    # Prevent "use lib" from doing anything when the .cgi files are compiled.
    # This is important to prevent the current directory from getting into
    # @INC and messing things up. (See bug 630750.)
    no warnings 'redefine';
    local *lib::import = sub { };
    use warnings;

    foreach my $file ( glob "$cgi_path/*.cgi" ) {
        my $base_filename = File::Basename::basename($file);
        if ( my $feature = $feature_files->{$base_filename} ) {
            next if !Bugzilla->feature($feature);
        }
        Bugzilla::Util::trick_taint($file);
        $rl->handler( $file, $file );
    }

    # Some items might already be loaded into the request cache
    # best to make sure it starts out empty.
    # Because of bug 1347335 we also do this in init_page().
    Bugzilla::clear_request_cache();
}

sub apache_config {
    my ($class, $cgi_path) = @_;

    Carp::croak "\$cgi_path is required" unless $cgi_path;

    my %htaccess;
    $cgi_path = Cwd::realpath($cgi_path);
    my $wanted = sub {
        package File::Find;
        our ($name, $dir);

        if ($name =~ m#/\.htaccess$#) {
            open my $fh, '<', $name or die "cannot open $name $!";
            my $contents = do {
                local $/ = undef;
                <$fh>;
            };
            close $fh;
            $htaccess{$dir} = { file => $name, contents => $contents, dir => $dir };
        }
    };

    File::Find::find( { wanted => $wanted, no_chdir => 1 }, $cgi_path );
    my $template = Template->new;
    my $conf;
    my %vars = (
        root_htaccess  => delete $htaccess{$cgi_path},
        htaccess_files => [ map { $htaccess{$_} } sort { length $a <=> length $b } keys %htaccess ],
        cgi_path       => $cgi_path,
    );
    $template->process(\*DATA, \%vars, \$conf);
    my $apache_version = Apache2::ServerUtil::get_server_version();
    if ($apache_version =~ m!Apache/(\d+)\.(\d+)\.(\d+)!) {
        my ($major, $minor, $patch) = ($1, $2, $3);
        if ($major > 2 || $major == 2 && $minor >= 4) {
            $conf =~ s{^\s+deny\s+from\s+all.*$}{Require all denied}gmi;
            $conf =~ s{^\s+allow\s+from\s+all.*$}{Require all granted}gmi;
            $conf =~ s{^\s+allow\s+from\s+(\S+).*$}{Require host $1}gmi;
        }
    }

    return $conf;
}

1;

__DATA__
# Make sure each httpd child receives a different random seed (bug 476622).
# Bugzilla::RNG has one srand that needs to be called for
# every process, and Perl has another. (Various Perl modules still use
# the built-in rand(), even though we never use it in Bugzilla itself,
# so we need to srand() both of them.)
PerlChildInitHandler "sub { Bugzilla::RNG::srand(); srand(); }"
PerlAccessHandler Bugzilla::ModPerl::BlockIP

# It is important to specify ErrorDocuments outside of all directories.
# These used to be in .htaccess, but then things like "AllowEncodedSlashes no"
# mean that urls containing %2f are unstyled.
ErrorDocument 401 /errors/401.html
ErrorDocument 403 /errors/403.html
ErrorDocument 404 /errors/404.html
ErrorDocument 500 /errors/500.html

<Directory "[% cgi_path %]">
    AddHandler perl-script .cgi
    # No need to PerlModule these because they're already defined in mod_perl.pl
    PerlResponseHandler Bugzilla::ModPerl::ResponseHandler
    PerlCleanupHandler Bugzilla::ModPerl::CleanupHandler Apache2::SizeLimit
    PerlOptions +ParseHeaders
    Options +ExecCGI +FollowSymLinks
    DirectoryIndex index.cgi index.html
    AllowOverride none
    # from [% root_htaccess.file %]
    [% root_htaccess.contents FILTER indent %]
</Directory>

# directory rules for all the other places we have .htaccess files
[% FOREACH htaccess IN htaccess_files %]
# from [% htaccess.file %]
<Directory "[% htaccess.dir %]">
    [% htaccess.contents FILTER indent %]
</Directory>
[% END %]
