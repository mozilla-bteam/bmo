# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::API::V1::Triage;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Extension::BMO::Reports::Triage;

use JSON::XS;

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/bmo/triage_owners')->to('BMO::API::V1::Triage#triage_owners');
}

sub triage_owners {
  my ($self) = @_;
  my $user = $self->bugzilla->login;

  # Here we are reusing the code that generates the triage owners report
  # accessible at https://bugzilla.mozilla.org/page.cgi?id=triage_owners.html
  my $vars  = {};
  my $input = {
    product   => $self->param('product'),
    component => $self->param('component'),
    owner     => $self->param('owner'),
  };
  Bugzilla::Extension::BMO::Reports::Triage::owners($vars, $input, 1);

  my $json = {};
  foreach my $result (@{$vars->{results}}) {
    $json->{$result->{product}} ||= {};
    $json->{$result->{product}}->{$result->{component}} = {
      triage_owner => ($result->{owner} ? $result->{owner}->login : ""),
      bug_counts   => $result->{bug_counts}
    };
  }

  return $self->render(status => 200, json => $json);
}

1;
