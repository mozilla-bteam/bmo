# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Teams;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
  get_team_info
  team_names
);

use JSON::MaybeXS qw(decode_json);
use JSON::PP::Boolean;
use List::MoreUtils qw(any);
use Try::Tiny qw(try catch);
use Type::Utils;
use Types::Standard qw(:types);

sub team_names {
  return Bugzilla->dbh->selectcol_arrayref(
    'SELECT DISTINCT team_name FROM components ORDER BY team_name'
  );
}

sub get_team_info {
  my @team_names = @_;
  my $teams_sql;

  my $query = "
    SELECT products.name AS product,
           components.name AS component,
           components.team_name AS team
      FROM components INNER JOIN products ON components.product_id = products.id";
  if (@team_names) {
    $query .= ' WHERE components.team_name IN (' . join(',', ('?') x @team_names) . ')';
  }
  $query .= " ORDER by components.team";

  my $rows
    = Bugzilla->dbh->selectall_arrayref($query, {'Slice' => {}}, @team_names);

  my $teams = {};
  foreach my $row (@{$rows}) {
    my $product   = $row->{product};
    my $component = $row->{component};
    my $team      = $row->{team};
    next if !Bugzilla->user->can_see_product($product);
    $teams->{$team} ||= {};
    $teams->{$team}->{$product} ||= [];
    push @{$teams->{$team}->{$product}}, $component;
  }

  return $teams;
}

1;

__END__
JSON syntax:

{
  <team name>: {
    <product name>: {
      "all_components": <boolean>,
      "named_components": [<component>, ..],
      "prefixed_components": [<prefix>, ..],
    },
    ..
  },
  ..
}

Example JSON:

{
  "Crypto": {
    "Core": {
      "all_components": false,
      "named_components": ["Security: PSM"],
      "prefixed_components": []
    },
    "JSS": {
      "all_components": true
    },
    "NSS": {
      "all_components": true
    }
  },
  "GFX": {
    "Core": {
      "all_components": false,
      "named_components": ["Canvas: 2D", "ImageLib", "Panning and Zooming", "Web Painting"],
      "prefixed_components": ["GFX", "Graphics"]
    }
  }
}

This defines two teams with the following components:
- Crypto
  - Core :: Security: PSM
  - JSS (all components)
  - NSS (all components)
- GFX
  - Core :: Canvas: 2D
  - Core :: ImageLib
  - Core :: Panning and Zooming
  - Core :: Web Painting
  - Core (all components starting with "GFX" or "Graphics")
