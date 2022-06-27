# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::BMO::NewRelease;

use 5.10.1;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Constants;
use Bugzilla::Product;
use Bugzilla::Milestone;
use Bugzilla::Version;
use Bugzilla::Token;
use Bugzilla::Util qw(fetch_product_versions trim);

use Scalar::Util qw(blessed);

sub setup_routes {
  my ($class, $r) = @_;
  $r->any('/admin/new_release')->to('BMO::NewRelease#new_release')
    ->name('new_release');
}

sub new_release {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO);
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) || return undef;

  $user->in_group('editcomponents')
    || return $self->user_error('auth_failure',
    {group => 'editcomponents', action => 'edit', object => 'milestones'});

  # Display the initial form
  if ($self->req->method ne 'POST') {
    my $versions          = fetch_product_versions('firefox');
    my $latest_nightly    = $versions->{FIREFOX_NIGHTLY};
    my ($current_nightly) = $latest_nightly =~ /^(\d+)/;

    my $selectable_products = $user->get_selectable_products || [];
    my $default_milestone_products
      = Bugzilla->params->{default_milestone_products} || [];
    my $default_version_products
      = Bugzilla->params->{default_version_products} || [];
    my $token = issue_session_token('new_release');

    my $vars = {
      next_release               => $current_nightly + 1,
      selectable_products        => $selectable_products,
      default_milestone_products => $default_milestone_products,
      default_version_products   => $default_version_products,
      token                      => $token
    };

    $self->stash(%{$vars});
    return $self->render(template => 'pages/new_release', handler => 'bugzilla');
  }

  # Check token data
  my $token = $self->param('token');
  check_token_data($token, 'new_release');
  delete_token($token);

  # Sanity check new values for milestone and version
  my $new_milestone = trim($self->param('new_milestone'));
  my $new_version   = trim($self->param('new_version'));
  $new_milestone =~ /^\d+$/
    || return $self->user_error("number_not_numeric",
    {field => 'milestone', num => $new_milestone});
  $new_version =~ /^\d+$/
    || return $self->user_error("number_not_numeric",
    {field => 'version', num => $new_version});

  # Process milestones
  my @results;
  foreach my $product (@{$self->every_param('milestone_products')}) {
    my $success
      = _add_value('milestone', $product, $new_milestone);
    my $result = {
      type    => 'milestone',
      product => $product,
      value   => "Firefox $new_milestone",
      success => $success
    };
    push @results, $result;
  }

  # Process versions
  foreach my $product (@{$self->every_param('version_products')}) {
    my $success      = _add_value('version', $product, $new_version);
    my $result       = {
      type    => 'version',
      product => $product,
      value   => "$new_version Branch",
      success => $success
    };
    push @results, $result;
  }

  $self->stash({results => \@results});
  return $self->render('pages/new_release', handler => 'bugzilla');
}

sub _add_value {
  my ($type, $product, $value) = @_;
  $product
    = blessed $product
    ? $product
    : Bugzilla::Product->new({name => $product, cache => 1});

  if ($type eq 'milestone') {
    my $full_milestone = "Firefox $value";

    if (!Bugzilla::Milestone->new({product => $product, name => $full_milestone})) {
      # Figure the proper sort key from the last version and add 10
      my $old_value = $value - 1;
      my $last_milestone = Bugzilla::Milestone->new({product => $product, name => "$old_value Branch"});
      my $sortkey = $last_milestone ? $last_milestone->sortkey + 10 : 0;

      # Need to add 10 to the current default milestone '---' so it is placed right above the new milestone
      my $default_milestone = Bugzilla::Milestone->new({product => $product, name => '---'});
      if ($default_milestone) {
        $default_milestone->set_sortkey($default_milestone->sortkey + 10);
        $default_milestone->update();
      }

      # Finally create the new milestone
      Bugzilla::Milestone->create({product => $product, value => $full_milestone, sortkey => $sortkey});
      return 1;
    }
    else {
      return 0;
    }
  }

  # Versions are simple in that they do not use sortkeys yet
  if ($type eq 'version') {
    my $full_version = "Firefox $value";

    if (!Bugzilla::Version->new({product => $product, name => $full_version})) {
      Bugzilla::Version->create({product => $product, value => $full_version});
      return 1;
    }
    else {
      return 0;
    }
  }
}

1;
