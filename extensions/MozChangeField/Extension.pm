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
use Bugzilla::Status qw(is_open_state);

use Module::Runtime qw(require_module);
use Mojo::Loader qw( find_modules );
use Try::Tiny;

our $VERSION = '0.1';

sub bug_check_can_change_field {
  my ($self, $args) = @_;
  my $user = Bugzilla->user;

  # Some modules need these so only look up once
  $args->{canconfirm} = $user->in_group('canconfirm', $args->{bug}->{'product_id'});
  $args->{editbugs}   = $user->in_group('editbugs',   $args->{bug}->{'product_id'});

  my $object_cache = Bugzilla->request_cache->{mozchangefield_object_cache} ||= {};

  foreach my $module (find_modules('Bugzilla::Extensions::MozChangeField')) {
    my $result;
    try {
      my $object = $object_cache->{$module};
      if (!$object) {
        require_module($module);
        $object = $module->new;
        next if !$object->can('process_field');
        $object_cache->{$module} = $object;
      }
      $result = $object->process($args);
    }
    catch {
      WARN("$module could not be loaded or processed: $_");
    };

    if (ref $result) {
      push @{$args->{priv_results}}, $result;
    }
  }
}

__PACKAGE__->NAME;
