#!/usr/bin/env perl
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
use Bugzilla::Config qw(:admin);
use Bugzilla::Config::Common;
use Bugzilla::Hook;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Status;
use Module::Runtime qw(require_module);

my $user     = Bugzilla->login(LOGIN_REQUIRED);
my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

print $cgi->header();

$user->in_group('tweakparams')
  || ThrowUserError("auth_failure",
  {group => "tweakparams", action => "access", object => "parameters"});

my $action        = trim($cgi->param('action') || '');
my $token         = $cgi->param('token');
my $current_panel = $cgi->param('section') || 'general';
$current_panel =~ /^([A-Za-z0-9_-]+)$/;
$current_panel = $1;

my $current_module;
my @panels       = ();
my $param_panels = Bugzilla::Config::param_panels();
my $override     = Bugzilla->localconfig->param_override;
foreach my $panel (keys %$param_panels) {
  my $module = $param_panels->{$panel};
  require_module($module);
  my @module_param_list = $module->get_param_list();
  my $item              = {
    name       => lc($panel),
    current    => ($current_panel eq lc($panel)) ? 1 : 0,
    param_list => \@module_param_list,
    param_override =>
      {map { $_->{name} => $override->{$_->{name}} } @module_param_list},
    sortkey => eval "\$${module}::sortkey;",
    module  => $module,
  };
  $item->{sortkey} //= 100000;
  push(@panels, $item);
  $current_module = $panel if ($current_panel eq lc($panel));
}

my %hook_panels = map { $_->{name} => {params => $_->{param_list}} } @panels;

# Note that this hook is also called in Bugzilla::Config.
Bugzilla::Hook::process('config_modify_panels', {panels => \%hook_panels});

$vars->{panels} = \@panels;

if ($action eq 'save' && $current_module) {
  # Check token data for CSRF protection
  check_token_data($token, 'edit_parameters');
  delete_token($token);

  my $config = Bugzilla::Config->new;
  my $param_defs = $hook_panels{$current_panel}->{params};
  my $new_params = $cgi->Vars; # Convert query parameters to a hash
  my $changes = $config->process_params($param_defs, $new_params);

  # allow panels to check inter-dependent params
  if (@{$changes}) {
    foreach my $panel (@panels) {
      next unless $panel->{name} eq lc $current_module;
      my $module = $panel->{module};
      next unless $module->can('check_params');
      my $err = $module->check_params(Bugzilla->params);
      if ($err ne '') {
        ThrowUserError('invalid_parameters', {err => $err});
      }
      last;
    }
  }

  $config->update();

  $vars->{'message'}       = 'parameters_updated';
  $vars->{'param_changed'} = $changes;
}

$vars->{'token'} = issue_session_token('edit_parameters');

$template->process("admin/params/editparams.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
