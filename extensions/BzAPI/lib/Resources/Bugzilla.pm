# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Resources::Bugzilla;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Keyword;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::Util ();

use Bugzilla::Extension::BzAPI::Constants;

use Digest::MD5 qw(md5_base64);

#########################
# REST Resource Methods #
#########################

BEGIN {
  require Bugzilla::WebService::Bugzilla;
  *Bugzilla::WebService::Bugzilla::get_configuration = \&get_configuration;
  *Bugzilla::WebService::Bugzilla::get_empty         = \&get_empty;
}

sub rest_handlers {
  my $rest_handlers = [
    qr{^/$},              {GET => {resource => {method => 'get_empty'}}},
    qr{^/configuration$}, {GET => {resource => {method => 'get_configuration'}}}
  ];
  return $rest_handlers;
}

sub get_configuration {
  my ($self) = @_;
  my $user   = Bugzilla->user;
  my $params = Bugzilla->input_params;

  my $can_cache = !exists $params->{product} && !exists $params->{flags};
  my $cache_key = 'bzapi_get_configuration';

  if ($can_cache) {
    my $result = Bugzilla->memcached->get_config({key => $cache_key});
    return $result if defined $result;
  }

  # Get data from the shadow DB as they don't change very often.
  Bugzilla->switch_to_shadow_db;

  # Pass a bunch of Bugzilla configuration to the templates.
  my $vars = {};
  $vars->{'priority'}   = get_legal_field_values('priority');
  $vars->{'severity'}   = get_legal_field_values('bug_severity');
  $vars->{'platform'}   = get_legal_field_values('rep_platform');
  $vars->{'op_sys'}     = get_legal_field_values('op_sys');
  $vars->{'keyword'}    = [map($_->name, Bugzilla::Keyword->get_all)];
  $vars->{'resolution'} = get_legal_field_values('resolution');
  $vars->{'status'}     = get_legal_field_values('bug_status');
  $vars->{'custom_fields'}
    = [grep { $_->is_select } Bugzilla->active_custom_fields];

  # Include a list of product objects.
  if ($params->{'product'}) {
    my @products = $params->{'product'};
    foreach my $product_name (@products) {
      my $product = new Bugzilla::Product({name => $product_name});
      if ($product && $user->can_see_product($product->name)) {
        push(@{$vars->{'products'}}, $product);
      }
    }
  }
  else {
    $vars->{'products'} = $user->get_selectable_products;
  }

  # We set the 2nd argument to 1 to also preload flag types.
  Bugzilla::Product::preload($vars->{'products'}, 1, {is_active => 1});

  # Allow consumers to specify whether or not they want flag data.
  if (defined $params->{'flags'}) {
    $vars->{'show_flags'} = $params->{'flags'};
  }
  else {
    # We default to sending flag data.
    $vars->{'show_flags'} = 1;
  }

  # Create separate lists of open versus resolved statuses.  This should really
  # be made part of the configuration.
  my @open_status;
  my @closed_status;
  foreach my $status (@{$vars->{'status'}}) {
    is_open_state($status)
      ? push(@open_status,   $status)
      : push(@closed_status, $status);
  }
  $vars->{'open_status'}   = \@open_status;
  $vars->{'closed_status'} = \@closed_status;

  # Generate a list of fields that can be queried.
  my @fields = @{Bugzilla::Field->match({obsolete => 0})};

  # Exclude fields the user cannot query.
  if (!Bugzilla->user->is_timetracker) {
    @fields = grep {
      $_->name
        !~ /^(estimated_time|remaining_time|work_time|percentage_complete|deadline)$/
    } @fields;
  }
  $vars->{'field'} = \@fields;

  my $json;
  Bugzilla->template->process('config.json.tmpl', $vars, \$json);
  if ($json) {
    my $result = $self->json->decode($json);
    if ($can_cache) {
      Bugzilla->memcached->set_config({key => $cache_key, data => $result});
    }
    return $result;
  }
  else {
    return {};
  }
}

sub get_empty {
  my ($self) = @_;
  return {
    ref => $self->type('string', Bugzilla->localconfig->{urlbase} . "bzapi/"),
    documentation => $self->type('string', BZAPI_DOC),
    version       => $self->type('string', BUGZILLA_VERSION)
  };
}

1;
