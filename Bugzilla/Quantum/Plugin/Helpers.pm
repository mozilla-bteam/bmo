# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Quantum::Plugin::Helpers;
use 5.10.1;
use Mojo::Base qw(Mojolicious::Plugin);

use Bugzilla::Logging;
use Carp;

sub register {
    my ( $self, $app, $conf ) = @_;

    $app->helper(
        basic_auth => sub {
            my ( $c, $realm, $auth_user, $auth_pass ) = @_;
            my $req = $c->req;
            my ( $user, $password ) = $req->url->to_abs->userinfo =~ /^([^:]+):(.*)/;

            unless ( $realm && $auth_user && $auth_pass ) {
                croak 'basic_auth() called with missing parameters.';
            }

            unless ( $user eq $auth_user && $password eq $auth_pass ) {
                WARN('username and password do not match');
                $c->res->headers->www_authenticate("Basic realm=\"$realm\"");
                $c->res->code(401);
                $c->rendered;
                return 0;
            }

            return 1;
        }
    );
    $app->routes->add_shortcut(
        static_file => sub {
            my ($r, $path, $real_file) = @_;
            unless ($real_file) {
                $real_file = $path;
                $real_file =~ s!^/!!;
            }

            return $r->get($file => sub {
                my ($c) = @_;
                $c->reply->file( $c->app->home->child($real_file) );
            })
        }
    );
    $app->routes->add_shortcut(
        page => sub {
            my ($r, $page, $id) = @_;
            $real_file //= $file;

            return $r->any($page)->to('CGI#page_cgi' => { id => $id });
        }
    );
}

1;
