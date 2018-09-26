#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;

my $cgi      = Bugzilla->cgi;
my $dbh      = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars     = {};

#
# Preliminary checks:
#

my $user = Bugzilla->login(LOGIN_REQUIRED);

print $cgi->header();

$user->in_group('admin')
    || ThrowUserError(
    "auth_failure",
    {
        group  => "admin",
        action => "edit",
        object => "oauth"
    }
    );

#
# often used variables
#

my $id     = trim( $cgi->param('id')     || '' );
my $id_old = trim( $cgi->param('id_old') || '' );
my $secret = trim( $cgi->param('secret') || '' );
my $action = trim( $cgi->param('action') || '' );
my $token  = $cgi->param('token');
my $active = $cgi->param('active');

#
# action = '' -> Show list of clients
#

unless ($action) {
    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );
    $vars->{'clients'} = $clients;
    $template->process( "admin/oauth/list.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='add' -> present form for parameters for new client
#
# (next action will be 'new')
#

if ( $action eq 'add' ) {
    $vars->{'token'} = issue_session_token('add_oauth_client');
    $template->process( "admin/oauth/create.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='new' -> add milestone entered in the 'action=add' screen
#

if ( $action eq 'new' ) {
    check_token_data( $token, 'add_oauth_client' );

    $id     || ThrowCodeError( 'param_required', { param => 'id' } );
    $secret || ThrowCodeError( 'param_required', { param => 'secret' } );

    $dbh->do( "INSERT INTO oauth2_client (id, secret) VALUES (?, ?)", undef, $id, $secret );

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_created';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $template->process( "admin/oauth/list.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='del' -> ask if user really wants to delete
#
# (next action would be 'delete')
#

if ( $action eq 'del' ) {
    my $client = $dbh->selectrow_hashref( "SELECT * FROM oauth2_client WHERE id = ?", undef, $id );

    $vars->{'client'} = $client;
    $vars->{'token'}  = issue_session_token('delete_oauth_client');
    $template->process( "admin/oauth/confirm-delete.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='delete' -> really delete the milestone
#

if ( $action eq 'delete' ) {
    check_token_data( $token, 'delete_oauth_client' );

    $dbh->do( "DELETE FROM oauth2_client WHERE id = ?", undef, $id );

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_deleted';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $template->process( "admin/oauth/list.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='edit' -> present the edit milestone form
#
# (next action would be 'update')
#

if ( $action eq 'edit' ) {
    my $client = $dbh->selectrow_hashref( "SELECT * FROM oauth2_client WHERE id = ?", undef, $id );

    $vars->{'client'} = $client;
    $vars->{'token'}  = issue_session_token('edit_oauth_client');
    $template->process( "admin/oauth/edit.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

#
# action='update' -> update the milestone
#

if ( $action eq 'update' ) {
    check_token_data( $token, 'edit_oauth_client' );

    my $client = $dbh->selectrow_hashref( "SELECT * FROM oauth2_client WHERE id = ?", undef, $id_old );

    if ( $secret ne $client->{secret} ) {
        $dbh->do( "UPDATE oauth2_client SET secret = ? WHERE id = ?", undef, $secret, $id_old );
    }
    if ( $active ne $client->{active} ) {
        $dbh->do( "UPDATE oauth2_client SET active = ? WHERE id = ?", undef, $active, $id_old );
    }
    if ( $id ne $id_old ) {
        $dbh->do( "UPDATE oauth2_client SET id = ? WHERE id = ?", undef, $id, $id_old );
    }

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_updated';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $template->process( "admin/oauth/list.html.tmpl", $vars )
        || ThrowTemplateError( $template->error() );
    exit;
}

# No valid action found
ThrowUserError( 'unknown_action', { action => $action } );
