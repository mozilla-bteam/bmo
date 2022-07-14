# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Constants;
use Module::Runtime qw(require_module);

use URI::QueryParam;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'bug_see_also';
use constant NAME_FIELD => 'value';
use constant LIST_ORDER => 'id';

# See Also is tracked in bugs_activity.
use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;

use constant DB_COLUMNS => qw(
  id
  bug_id
  value
  class
);

# This must be strings with the names of the validations,
# instead of coderefs, because subclasses override these
# validators with their own.
use constant VALIDATORS => {
  value  => '_check_value',
  bug_id => '_check_bug_id',
  class  => \&_check_class,
};

# This is the order we go through all of subclasses and
# pick the first one that should handle the URL. New
# subclasses should be added at the end of the list.
use constant SUB_CLASSES => qw(
  Bugzilla::BugUrl::Local
  Bugzilla::BugUrl::External
);

###############################
####      Accessors      ######
###############################

sub class  { return $_[0]->{class} }
sub bug_id { return $_[0]->{bug_id} }

###############################
####        Methods        ####
###############################

sub new {
  my $class = shift;
  my $param = shift;

  if (ref $param) {
    my $bug_id = $param->{bug_id};
    my $name = $param->{name} || $param->{value};
    if (!defined $bug_id) {
      ThrowCodeError('bad_arg', {argument => 'bug_id', function => "${class}::new"});
    }
    if (!defined $name) {
      ThrowCodeError('bad_arg', {argument => 'name', function => "${class}::new"});
    }

    my $condition = 'bug_id = ? AND value = ?';
    my @values = ($bug_id, $name);
    $param = {condition => $condition, values => \@values};
  }

  unshift @_, $param;
  return $class->SUPER::new(@_);
}

sub _do_list_select {
  my $class   = shift;
  my $objects = $class->SUPER::_do_list_select(@_);

  foreach my $object (@$objects) {
    require_module($object->class);
    bless $object, $object->class;
  }

  return $objects;
}

# This is an abstract method. It must be overridden
# in every subclass.
sub should_handle {
  my ($class, $input) = @_;
  ThrowCodeError('unknown_method', {method => "${class}::should_handle"});
}

sub class_for {
  my ($class, $value) = @_;

  my $uri = URI->new($value);
  foreach my $subclass ($class->SUB_CLASSES) {
    require_module($subclass);
    return wantarray ? ($subclass, $uri) : $subclass
      if $subclass->should_handle($uri);
  }

  ThrowUserError('bug_url_invalid', {url => $value, reason => 'show_bug'});
}

sub _check_class {
  my ($class, $subclass) = @_;
  require_module($subclass);
  return $subclass;
}

sub _check_bug_id {
  my ($class, $bug_id) = @_;

  my $bug;
  if (blessed $bug_id) {

    # We got a bug object passed in, use it
    $bug = $bug_id;
    $bug->check_is_visible;
  }
  else {
    # We got a bug id passed in, check it and get the bug object
    $bug = Bugzilla::Bug->check({id => $bug_id});
  }

  return $bug->id;
}

sub _check_value {
  my ($class, $uri) = @_;

  my $value = $uri->as_string;

  if (!$value) {
    ThrowCodeError('param_required',
      {function => 'add_see_also', param => '$value'});
  }

  return $uri;
}

1;
