# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Home;
use Mojo::Base 'Mojolicious::Controller';

use Bugzilla::Error;
use Try::Tiny;
use Bugzilla::Constants;


sub setup_routes {
  my ($class, $r) = @_;

  $r->get('/home')->to('Home#index');
  $r->get('/home/special.css')->to('Home#special_css');
}

sub index {
  my ($c) = @_;
  $c->bugzilla->login(LOGIN_REQUIRED) or return;
  try {
    ThrowUserError('invalid_username', {login => 'batman'}) if $c->param('error');
    $c->render(handler => 'bugzilla', template => 'index');
  }
  catch {
    $c->bugzilla->error_page($_);
  };
}

sub special_css {
  my ($c) = @_;

  my $user = $c->bugzilla->login(LOGIN_OPTIONAL);
  $c->render(handler => 'bugzilla', user => $user, format => 'css');
}

1;
