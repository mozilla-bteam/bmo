# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Rules;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::Extension);

use Mojo::Util qw(trim);
use Bugzilla::Extension::Rules::Sandbox;

our $VERSION = '0.01';

my $Safe = Safe->new;
$Safe->share_from('Bugzilla::Extension::Rules::Sandbox',
  ['&group', '&field', '&product', '&deny']);
$Safe->permit_only(
  qw(
    :base_core
    gvsv gv gelem padsv padav padhv padany once rv2gv refgen srefgen ref
    pushre regcmaybe regcreset regcomp subst substcont
    )
);


sub bug_check_can_change_field {
  my ($self, $args) = @_;

  local $Bugzilla::Extension::Rules::Sandbox::BUG   = $args->{bug};
  local $Bugzilla::Extension::Rules::Sandbox::FIELD = $args->{field};
  local $Bugzilla::Extension::Rules::Sandbox::PRIV_RESULTS = $args->{priv_results};
  $Safe->reval( Bugzilla->params->{can_change_field_rules} . "; 1" )
  or die $@;
}

sub config_modify_panels {
  my ($self, $args) = @_;

  push @{$args->{panels}->{advanced}->{params}},
    {name => 'can_change_field_rules', type => 'l', default => '',};
}


__PACKAGE__->NAME;
