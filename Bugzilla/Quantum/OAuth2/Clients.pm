# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::OAuth2::Clients;
use Mojo::Base 'Mojolicious::Controller';

use 5.10.1;
use Moo;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Token;

# Show list of clients
sub list {
    my ( $self ) = @_;
    my $clients = Bugzilla->dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );
    $self->stash(clients => $clients);
    return $self->render( template => 'admin/oauth/list', handler => 'bugzilla' );
}

# Create new client
sub create {
    my ( $self ) = @_;
    my $dbh = Bugzilla->dbh;
    my $vars = {};

    if ($self->req->method ne 'POST') {
        $vars->{token} = issue_session_token('create_oauth_client');
        $self->stash(%$vars);
        return $self->render( template => 'admin/oauth/create', handler => 'bugzilla' );
    }

    my $id     = $self->param('id');
    my $secret = $self->param('secret');
    $id     || ThrowCodeError( 'param_required', { param => 'id' } );
    $secret || ThrowCodeError( 'param_required', { param => 'secret' } );

    my $token = $self->param('token');
    check_token_data( $token, 'create_oauth_client' );

    $dbh->do( "INSERT INTO oauth2_client (id, secret) VALUES (?, ?)", undef, $id, $secret );

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_created';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $self->stash(%$vars);
    return $self->render( template => 'admin/oauth/list', handler => 'bugzilla' );
}

# Delete client
sub delete {
    my ( $self ) = @_;
    my $dbh  = Bugzilla->dbh;
    my $vars = {};

    my $id     = $self->param('id');
    my $client = $dbh->selectrow_hashref( "SELECT * FROM oauth2_client WHERE id = ?", undef, $id );

    if (!$self->param('deleteme')) {
        $vars->{'client'} = $client;
        $vars->{'token'}  = issue_session_token('delete_oauth_client');
        $self->stash(%$vars);
        return $self->render( template => 'admin/oauth/confirm-delete', handler => 'bugzilla' );
    }

    my $token = $self->param('token');
    check_token_data( $token, 'delete_oauth_client' );

    $dbh->do( "DELETE FROM oauth2_client WHERE id = ?", undef, $id );

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_deleted';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $self->stash(%$vars);
    return $self->render( template => 'admin/oauth/list', handler => 'bugzilla' );
}

#  Edit client
sub edit {
    my ( $self ) = @_;
    my $dbh  = Bugzilla->dbh;
    my $vars = {};

    my $id = $self->param('id');
    my $client = $dbh->selectrow_hashref( "SELECT * FROM oauth2_client WHERE id = ?", undef, $id );

    if ($self->req->method ne 'POST') {
        $vars->{'client'} = $client;
        $vars->{'token'}  = issue_session_token('edit_oauth_client');
        $self->stash(%$vars);
        return $self->render( template => 'admin/oauth/edit', handler => 'bugzilla' );
    }

    my $token = $self->param('token');
    check_token_data( $token, 'edit_oauth_client' );

    my $secret = $self->param('secret');
    my $active = $self->param('active');
    my $id_old = $self->param('id_old');

    if ( $secret ne $client->{secret} ) {
        $dbh->do( "UPDATE oauth2_client SET secret = ? WHERE id = ?", undef, $secret, $id_old );
    }
    if ( $active ne $client->{active} ) {
        $dbh->do( "UPDATE oauth2_client SET active = ? WHERE id = ?", undef, $active, $id_old );
    }
    if ( $id_old ne $id  ) {
        $dbh->do( "UPDATE oauth2_client SET id = ? WHERE id = ?", undef, $id, $id_old );
    }

    delete_token($token);

    my $clients = $dbh->selectall_arrayref( "SELECT * FROM oauth2_client", { Slice => {} } );

    $vars->{'message'} = 'oauth_client_updated';
    $vars->{'client'}  = { id => $id };
    $vars->{'clients'} = $clients;
    $self->stash(%$vars);
    return $self->render( template => 'admin/oauth/list', handler => 'bugzilla' );
}

1;
