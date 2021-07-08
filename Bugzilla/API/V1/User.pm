# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::User;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );
use Mojo::JSON qw( true false );

use Bugzilla::Constants;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/user_profile')->to('V1::User#user_profile');
}

sub user_profile {
  my ($self) = @_;
  my $user = $self->bugzilla->oauth('user:read');
  if ($user && $user->id) {
    $self->render(
      json => {
        id                    => $user->id,
        name                  => $user->name,
        login                 => $user->login,
        nick                  => $user->nick,
        groups                => [map { $_->name } @{$user->groups}],
        mfa                   => lc($user->mfa),
        mfa_required_by_group => $user->in_mfa_group ? true : false,
        iam_username          => $user->iam_username,
      }
    );
  }
  else {
    return $self->user_error('invalid_username');
  }
}

1;
