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
  component_to_team_name
  check_value
);

use JSON::MaybeXS qw(decode_json);
use JSON::PP::Boolean;
use List::MoreUtils qw(any);
use Try::Tiny qw(try catch);
use Type::Utils;
use Types::Standard qw(:types);

sub component_to_team_name {
  # Use the `report_component_teams` parameter to return the Team Name for the
  # specified product and component.  Returns `undef` if no matching team name
  # is found.
  # This function provides a request level cache around calls to
  # _component_to_team_name().
  my ($product, $component) = @_;

  my $cache = Bugzilla->request_cache->{team_name_cache} //= {};
  my $key = $product . "\n" . $component;
  if (!(exists $cache->{$key})) {
    $cache->{$key} = _component_to_team_name($product, $component);
  }

  return $cache->{$key};
}

sub _component_to_team_name {
  my ($product, $component) = @_;

  my $teams = Bugzilla->request_cache->{report_component_teams} //= decode_json(
    Bugzilla->params->{report_component_teams}
  );

  foreach my $team_name (keys %$teams) {
    my $team = $teams->{$team_name};
    next unless exists $team->{$product};
    return $team_name
      if $team->{$product}->{all_components};
    return $team_name
      if any { lc $component eq lc $_ } @{$team->{$product}->{named_components}};
    return $team_name
      if any { $component =~ /^\Q$_\E/i } @{$team->{$product}->{prefixed_components}};
  }
  return undef;
}

my $JSONBool = class_type {class => 'JSON::PP::Boolean'};
my $json_structure = HashRef [
  HashRef [
    Dict [
      all_components      => $JSONBool,
      prefixed_components => Optional [ArrayRef [Str]],
      named_components    => Optional [ArrayRef [Str]],
    ],
  ],
];

sub check_value {
  my ($string_value) = @_;

  my $value;
  my $ok = try {
    $value = decode_json($string_value);
  } catch {
    return undef;
  };
  return 'Malformed JSON' unless $ok;

  return $json_structure->check($value) ? '' : 'Invalid structure';
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
