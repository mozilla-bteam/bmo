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

use constant TEMPLATES => {
  milestone => {'_default' => '%%% Branch'},
  version   => {
    'Calendar'      => 'Thunderbird %%%',
    'Chat Core'     => 'Thunderbird %%%',
    'MailNews Core' => 'Thunderbird %%%',
    'SeaMonkey'     => 'SeaMonkey 2.%%%',
    'Thunderbird'   => 'Thunderbird %%%',
    '_default'      => 'Firefox %%%'
  }
};

sub setup_routes {
  my ($class, $r) = @_;
  $r->any('/admin/new_release')->to('BMO::NewRelease#new_release')
    ->name('new_release');
}

sub new_release {
  my ($self) = @_;
  Bugzilla->usage_mode(USAGE_MODE_MOJO);
  my $user = $self->bugzilla->login(LOGIN_REQUIRED) || return undef;

  $user->in_group('edittrackingflags')
    || return $self->user_error('auth_failure',
    {group => 'edittrackingflags', action => 'edit', object => 'milestones'});

  # Display the initial form
  if ($self->req->method eq 'GET') {
    my $versions          = fetch_product_versions('firefox');
    return $self->code_error() if !$versions;

    my $latest_nightly    = $versions->{FIREFOX_NIGHTLY};
    my ($current_nightly) = $latest_nightly =~ /^(\d+)/;

    my $selectable_products = $user->get_selectable_products || [];
    my $default_milestone_products
      = [ split /\n/, Bugzilla->params->{default_milestone_products} ];
    my $default_version_products
      = [ split /\n/, Bugzilla->params->{default_version_products} ];
    my $token = issue_session_token('new_release');

    my $vars = {
      next_release               => $current_nightly + 1,
      old_release                => $current_nightly - 15,
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
  my $old_milestone = trim($self->param('old_milestone'));
  my $new_version   = trim($self->param('new_version'));
  my $old_version   = trim($self->param('old_version'));

  $new_milestone =~ /^\d+$/
    || return $self->user_error('number_not_numeric',
    {field => 'new_milestone', num => $new_milestone});
  $new_version =~ /^\d+$/
    || return $self->user_error('number_not_numeric',
    {field => 'new_version', num => $new_version});

  if ($old_milestone && $old_milestone !~ /^\d+$/) {
    return $self->user_error('number_not_numeric',
      {field => 'old_milestone', num => $old_milestone});
  }

  if ($old_version && $old_version !~ /^\d+$/) {
    return $self->user_error('number_not_numeric',
      {field => 'old_version', num => $old_version});
  }

  # Process milestones
  my @results;
  foreach my $product (@{$self->every_param('milestone_products')}) {
    my $success = _add_value($product, $new_milestone, 'milestone');
    my $result  = {
      type    => 'new_milestone',
      product => $product,
      value   => _get_formatted_value($product, $new_milestone, 'milestone'),
      success => $success
    };
    push @results, $result;

    if ($old_milestone) {
      $success = _disable_value($product, $old_milestone, 'milestone');
      $result = {
        type    => 'old_milestone',
        product => $product,
        value   => _get_formatted_value($product, $old_milestone, 'milestone'),
        success => $success
      };
      push @results, $result;
    }
  }

  # Process versions
  foreach my $product (@{$self->every_param('version_products')}) {
    my $success = _add_value($product, $new_version, 'version');
    my $result  = {
      type    => 'new_version',
      product => $product,
      value   => _get_formatted_value($product, $new_version, 'version'),
      success => $success
    };
    push @results, $result;

    if ($old_version) {
      $success = _disable_value($product, $old_version, 'version');
      $result = {
        type    => 'old_version',
        product => $product,
        value   => _get_formatted_value($product, $old_version, 'version'),
        success => $success
      };
      push @results, $result;
    }
  }

  $self->stash({results => \@results});
  return $self->render('pages/new_release', handler => 'bugzilla');
}

sub _add_value {
  my ($product, $value, $type) = @_;
  $product
    = blessed $product
    ? $product
    : Bugzilla::Product->new({name => $product, cache => 1});

  if ($type eq 'milestone') {
    my $new_milestone = _get_formatted_value($product->name, $value, 'milestone');
    my $old_milestone
      = _get_formatted_value($product->name, $value - 1, 'milestone');

    if (!Bugzilla::Milestone->new({product => $product, name => $new_milestone})) {

      # Figure out the proper sort key from the last version and add 10
      my $last_milestone
        = Bugzilla::Milestone->new({product => $product, name => $old_milestone});
      my $sortkey = $last_milestone ? $last_milestone->sortkey + 10 : 0;

      # Need to add 10 to the current default milestone '---'
      # so it is placed right above the new milestone
      my $default_milestone
        = Bugzilla::Milestone->new({product => $product, name => '---'});
      if ($default_milestone) {
        $default_milestone->set_sortkey($default_milestone->sortkey + 10);
        $default_milestone->update();
      }

      # Finally create the new milestone
      Bugzilla::Milestone->create(
        {product => $product, value => $new_milestone, sortkey => $sortkey});
      return $new_milestone;
    }
  }

  # Versions are simple in that they do not use sortkeys yet
  if ($type eq 'version') {
    my $new_version = _get_formatted_value($product->name, $value, 'version');
    if (!Bugzilla::Version->new({product => $product, name => $new_version})) {
      Bugzilla::Version->create({product => $product, value => $new_version});
      return $new_version;
    }
  }

  return 0;
}

sub _disable_value {
  my ($product, $value, $type) = @_;
  $product
    = blessed $product
    ? $product
    : Bugzilla::Product->new({name => $product, cache => 1});

  if ($type eq 'milestone') {
    my $old_milestone = _get_formatted_value($product->name, $value, 'milestone');

    if (my $milestone_obj
      = Bugzilla::Milestone->new({product => $product, name => $old_milestone}))
    {
      $milestone_obj->set_is_active(0);
      $milestone_obj->update();
      return 1;
    }
  }

  # Versions are simple in that they do not use sortkeys yet
  if ($type eq 'version') {
    my $old_version = _get_formatted_value($product->name, $value, 'version');
    if (my $version_obj
      = Bugzilla::Version->new({product => $product, name => $old_version}))
    {
      $version_obj->set_is_active(0);
      $version_obj->update();
      return 1;
    }
  }

  return 0;
}

# Helper function to return a fully formatted version or milestone
sub _get_formatted_value {
  my ($product, $value, $type) = @_;
  my $template
    = exists TEMPLATES->{$type}->{$product}
    ? TEMPLATES->{$type}->{$product}
    : TEMPLATES->{$type}->{_default};
  my $formatted_value = $template;
  $formatted_value =~ s/%%%/$value/;
  return $formatted_value;
}

1;
