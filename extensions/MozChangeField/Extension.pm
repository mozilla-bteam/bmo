# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Logging;

use File::Basename qw(basename);
use Module::Runtime qw(require_module);
use Try::Tiny;

our $VERSION = '0.1';

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my $user = Bugzilla->user;

  # Some modules need these so only look up once
  $args->{canconfirm}
    = $user->in_group('canconfirm', $args->{bug}->{'product_id'});
  $args->{editbugs} = $user->in_group('editbugs', $args->{bug}->{'product_id'});

  my $object_cache = Bugzilla->request_cache->{mozchangefield_object_cache}
    ||= {};

  foreach my $full_file (
    glob bz_locations->{'extensionsdir'} . '/MozChangeField/lib/*.pm')
  {
    my $filename = basename($full_file, '.pm');
    my $class    = "Bugzilla::Extension::MozChangeField::$filename";

    my $result;

    try {
      my $object = $object_cache->{$class};
      if (!$object) {
        require $full_file;
        $object = $class->new;
        next if !$object->can('evaluate_change');
        $object_cache->{$class} = $object;
      }
      $result = $object->evaluate_change($args);
    }
    catch {
      WARN("$class could not be loaded or processed: $_");
    };

    if (ref $result) {
      push @{$args->{priv_results}}, $result;
    }
  }
}

__PACKAGE__->NAME;
