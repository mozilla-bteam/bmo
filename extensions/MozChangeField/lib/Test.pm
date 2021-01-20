# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Test;

use 5.10.1;
use Moo;

use Bugzilla::Constants;
use Bugzilla::Logging;

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $old_value    = $args->{'old_value'};
  my $priv_results = $args->{'priv_results'};
  my $canconfirm   = $args->{'canconfirm'};
  my $editbugs     = $args->{'editbugs'};

  # if ($field eq 'priority' && !$editbugs) {
  #   return {
  #     result => PRIVILEGES_REQUIRED_EMPOWERED,
  #     reason => 'You require "editbugs" permission to reopen a RESOLVED/VERIFIED bug',
  #   };
  # }

  return undef;
}

1;
