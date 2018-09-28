package Bugzilla::Quantum::Product;

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Logging;
use Bugzilla::Constants qw(ERROR_MODE_DIE);
use Bugzilla::User ();
use Try::Tiny;

sub list {
    my ($c) = @_;
    my $v = $c->validation;

    $v->optional('include_components');
    $v->optional('include_milestones');
    $v->optional('include_components');
    $v->optional('include_flag_types');

    my $user = Bugzilla->user;

    Bugzilla->switch_to_shadow_db();
    my $type = $c->param('type');
    my $products;
    if ( $type eq 'accessible' ) {
        $products = $user->get_accessible_products();
    }
    elsif ( $type eq 'enterable' ) {
        $products = $user->get_enterable_products();
    }
    elsif ( $type eq 'selectable' ) {
        $products = $user->get_selectable_products();
    }
    else {
        my $msg = "unknown value in placeholder 'type': $type";
        FATAL($msg);
        $c->render( json => { error => "$msg" }, code => 500 );
        return;
    }

    # Now create a result entry for each.
    my @products = map { _product_to_hash( $_, $v ) } @$products;
    $c->render( json => { products => \@products } );
}

sub _product_to_hash {
    my ( $product, $v ) = @_;

    my $product_hash = {
        id                => $product->id,
        name              => $product->name,
        description       => $product->description,
        is_active         => $product->is_active,
        default_milestone => $product->default_milestone,
        has_unconfirmed   => $product->allows_unconfirmed,
        classification    => $product->classification->name,
    };
    if ( $v->param('include_components') ) {
        $product_hash->{components}
            = [ map { _component_to_hash( $_, $v ) } @{ $product->components } ];
    }
    if ( $v->param('include_versions') ) {
        $product_hash->{versions} = [ map { _version_to_hash($_) } @{ $product->versions } ];
    }
    if ( $v->param('include_milestones') ) {
        $product_hash->{milestones}
            = [ map { _milestone_to_hash($_) } @{ $product->milestones } ];
    }

    $product_hash->{default_platform} = $product->default_platform;
    $product_hash->{default_op_sys}   = $product->default_op_sys;

    # BMO - add default security group
    $product_hash->{default_security_group} = $product->default_security_group;

    return $product_hash;
}

sub _component_to_hash {
    my ( $component, $v ) = @_;
    my $component_hash = {
        id                  => $component->id,
        name                => $component->name,
        description         => $component->description,
        default_assigned_to => $component->default_assignee->login,
        default_qa_contact  => $component->default_qa_contact->login,
        is_active           => $component->is_active,
        sort_key            => 0,                                       # sort_key is returned to match Bug.fields
    };

    if ( $v->param('include_flag_types') ) {
        $component_hash->{flag_types} = {
            bug        => [ map { _flag_type_to_hash($_) } @{ $component->flag_types->{'bug'} } ],
            attachment => [ map { _flag_type_to_hash($_) } @{ $component->flag_types->{'attachment'} } ],
        };
    }

    return $component_hash;
}

sub _flag_type_to_hash {
    my ( $flag_type, $v ) = @_;
    return {
        id               => $flag_type->id,
        name             => $flag_type->name,
        description      => $flag_type->description,
        cc_list          => $flag_type->cc_list,
        sort_key         => $flag_type->sortkey,
        is_active        => $flag_type->is_active,
        is_requestable   => $flag_type->is_requestable,
        is_requesteeble  => $flag_type->is_requesteeble,
        is_multiplicable => $flag_type->is_multiplicable,
        grant_group      => $flag_type->grant_group_id,
        request_group    => $flag_type->request_group_id,
    };
}

sub _version_to_hash {
    my ($version) = @_;
    return {
        id        => $version->id,
        name      => $version->name,
        sort_key  => 0,                     # sort_key is returened to match Bug.fields
        is_active => $version->is_active,
    };
}

sub _milestone_to_hash {
    my ( $self, $milestone, $params ) = @_;
    return {
        id        => $milestone->id,
        name      => $milestone->name,
        sort_key  => $milestone->sortkey,
        is_active => $milestone->is_active,
    };
}

1;
