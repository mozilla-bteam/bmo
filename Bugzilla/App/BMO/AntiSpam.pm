# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::BMO::AntiSpam;

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
  my @panels         = ();
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

    my $item
      = {name => lc $panel, param_list => \@module_param_list, module => $module,};
    push @panels, $item;
  }

  $vars->{panels} = \@panels;

  if ($self->req->method eq 'POST') {

    # Check token data
    my $token = $self->param('token');
    check_token_data($token, 'edit_antispam_params');

    my @changes     = ();
    my $any_changed = 0;

    foreach my $panel (@panels) {
      foreach my $param (@{$panel->{param_list}}) {
        my $name  = $param->{name};
        my $value = $self->param($name);

        if (defined $self->param("reset-$name") && !$param->{no_reset}) {
          $value = $param->{default};
        }
        else {
          if ($param->{type} eq 'm') {

            # This simplifies the code below
            $value = [$self->param($name)];
          }
          else {
            # Get rid of windows/mac-style line endings.
            $value =~ s/\r\n?/\n/g;

            # assume single linefeed is an empty string
            $value =~ s/^\n$//;
          }
        }

        my $changed;
        if ($param->{type} eq 'm') {
          my @old = sort @{Bugzilla->params->{$name}};
          my @new = sort @$value;
          if (scalar @old != scalar @new) {
            $changed = 1;
          }
          else {
            $changed = 0;    # Assume not changed...
            my $total_items = scalar @old;
            my $count = 0;
            while ($count < $total_items) {
              if ($old[$count] ne $new[$count]) {
                # entry is different, therefore changed
                $changed = 1;
                last;
              }
              $count++;
            }
          }
        }
        else {
          $changed = ($value eq Bugzilla->params->{$name}) ? 0 : 1;
        }

        if ($changed) {
          if (exists $param->{'checker'}) {
            my $ok = $param->{'checker'}->($value, $param);
            return $self->user_error('invalid_parameter', {name => $name, err => $ok}) if $ok ne '';
          }
          push @changes, $name;
          SetParam($name, $value);
          $any_changed = 1;
        }
      }
    }

    $vars->{'message'}       = 'parameters_updated';
    $vars->{'param_changed'} = \@changes;

    write_params();
    delete_token($token);
  }

  $vars->{'token'} = issue_session_token('edit_antispam_params');
  $self->stash(%{$vars});
  return $self->render(template => 'pages/antispam', handler => 'bugzilla');
}

1;
