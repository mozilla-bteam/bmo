# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Pre::CustomField;

use 5.10.1;
use Moo;

use Bugzilla::Constants;

# Who can set custom flags (use full field names only, not regex's)
our $cf_setters
  = {'cf_colo_site' => ['infra', 'build'], 'cf_rank' => ['rank-setters'],};

sub evaluate_change {
  my ($self, $args) = @_;

  my $bug          = $args->{'bug'};
  my $field        = $args->{'field'};
  my $new_value    = $args->{'new_value'};
  my $priv_results = $args->{'priv_results'};
  my $user         = Bugzilla->user;

  return undef if $field !~ /^cf/;

  if (!@$priv_results && $new_value ne '---') {


    # Custom field setters restrictions
    if (exists $cf_setters->{$field}) {
      my $in_group = 0;
      foreach my $group (@{$cf_setters->{$field}}) {
        if ($user->in_group($group, $bug->product_id)) {
          $in_group = 1;
          last;
        }
      }
      if (!$in_group) {
        return {
          result => PRIVILEGES_REQUIRED_EMPOWERED,
          reason => 'Specific permissions are required to make this change.',
        };
      }
    }
  }

  return undef;
}

1;
