# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Controller::BMO::AntiSpam;

use 5.10.1;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Config qw(SetParam write_params);
use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Token;

use List::Util      qw(first);
use Module::Runtime qw(require_module);

sub setup_routes {
  my ($class, $r) = @_;
  $r->any('/admin/antispam')->to('BMO::AntiSpam#antispam')->name('antispam');
}

sub antispam {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO);
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) || return undef;

  $user->in_group('can_configure_antispam')
    || return $self->user_error('auth_failure',
    {group => 'can_configure_antispam', action => 'edit', object => 'parameters'});

  my $current_module = '';
  my $param_panels   = Bugzilla::Config::param_panels();
  my $param_defs     = [];
  my $vars           = {};

  foreach my $panel (keys %{$param_panels}) {

    # We only want AntiSpam and Auth
    next if $panel ne 'AntiSpam' && $panel ne 'Auth';

    my $module = $param_panels->{$panel};
    require_module($module);
    my @module_param_list = $module->get_param_list();

    # For the Auth panel, we only want allow_account_creation
    if ($panel eq 'Auth') {
      @module_param_list
        = first { $_->{name} eq 'allow_account_creation' } @module_param_list;
    }

    push @{$param_defs}, @module_param_list;
  }

  $vars->{panels} = [{name => 'antispam', param_list => $param_defs}];

  if ($self->req->method eq 'POST') {

    # Check token data for CSRF protection
    my $token = $self->param('token');
    check_token_data($token, 'edit_antispam_params');
    delete_token($token);

    my $config     = Bugzilla::Config->new;
    my $new_params = $self->req->body_params->to_hash;
    my $changes    = $config->process_params($param_defs, $new_params);
    $config->update();

    $vars->{'message'}       = 'parameters_updated';
    $vars->{'param_changed'} = $changes;
  }

  $vars->{'token'} = issue_session_token('edit_antispam_params');
  $self->stash(%{$vars});
  return $self->render(template => 'pages/antispam', handler => 'bugzilla');
}

1;
