# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Param;

use base qw(Bugzilla::Object);

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;

use Scalar::Util qw(looks_like_number);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'params';

use constant DB_COLUMNS => qw(
  id
  name
  value_text
  value_numeric
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => qw(
  name
  value_text
  value_numeric
);

use constant VALIDATORS => {
  name          => \&_check_name,
  value_text    => \&_check_value,
  value_numeric => \&_check_value,
};

sub create {
  my ($class, $params) = @_;
  my $create_params = {name => $params->{name}};
  if (looks_like_number($params->{value})) {
    $create_params->{value_numeric} = $params->{value};
  }
  else {
    $create_params->{value_text} = $params->{value};
  }
  return $class->SUPER::create($create_params);
}

###############################
####      Validators       ####
###############################

sub _check_name {
  my ($invocant, $name) = @_;
  defined $name || ThrowCodeError('param_required', {param => 'name'});
  return $name;
}

sub _check_value {
  my ($invocant, $value) = @_;
  defined $value || ThrowCodeError('param_required', {param => 'value'});
  return $value;
}

###############################
####       Setters         ####
###############################

sub set_name { $_[0]->set('name', $_[1]); }

sub set_value {
  my ($self, $value) = @_;
  if (looks_like_number($value)) {
    $self->set('value_numeric', $value);
  }
  else {
    $self->set('value_text', $value);
  }
}

###############################
####      Accessors        ####
###############################

sub name { return $_[0]->{name}; }

sub value {
  my $self = shift;
  return
    defined $self->{value_text} ? $self->{value_text} : $self->{value_numeric};
}

sub is_numeric {
  return defined $_[0]->{value_text} ? 0 : 1;
}

1;
