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
  value
);

use constant UPDATE_COLUMNS => qw(
  name
  value
);

use constant VALIDATORS => {name => \&_check_name, value => \&_check_value,};

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

sub set_name  { $_[0]->set('name',  $_[1]); }
sub set_value { $_[0]->set('value', $_[1]); }

###############################
####      Accessors        ####
###############################

sub name  { return $_[0]->{name};  }
sub value { return $_[0]->{value}; }

sub is_numeric {
  return looks_like_number($_[0]->{value}) ? 1 : 0;
}

1;
