#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Component;
use Bugzilla::Product;

use Mojo::JSON qw(decode_json);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $teams = decode_json(Bugzilla->params->{report_component_teams});

my $dbh = Bugzilla->dbh;

$dbh->bz_start_transaction();

foreach my $team_name (keys %{$teams}) {
  my $team = $teams->{$team_name};
  foreach my $product (keys %{$team}) {
    my $product_obj = Bugzilla::Product->new({name => $product, cache => 1});
    if ($team->{$product}->{all_components}) {
      my $components = Bugzilla::Component->match({product_id => $product_obj->id});
      foreach my $component_obj (@{$components}) {
        Bugzilla->input_params->{watch_user} = $component_obj->watch_user->login;
        $component_obj->set_team_name($team_name);
        $component_obj->update();
      }
    }
    else {
      foreach my $component (@{$team->{$product}->{named_components}}) {
        my $component_obj = Bugzilla::Component->new(
          {name => $component, product => $product_obj, cache => 1});
        Bugzilla->input_params->{watch_user} = $component_obj->watch_user->login;
        $component_obj->set_team_name($team_name);
        $component_obj->update();
      }
      foreach my $prefix (@{$team->{$product}->{prefixed_components}}) {
        my $component_ids = $dbh->selectcol_arrayref(
          "SELECT id FROM components WHERE name LIKE '"
            . $prefix
            . "%' AND product_id = ?",
          undef, $product_obj->id
        );
        foreach my $component_id (@{$component_ids}) {
          my $component_obj = Bugzilla::Component->new({id => $component_id, cache => 1});
          Bugzilla->input_params->{watch_user} = $component_obj->watch_user->login;
          $component_obj->set_team_name($team_name);
          $component_obj->update();
        }
      }
    }
  }
}

$dbh->do("UPDATE components SET team_name = 'Mozilla' WHERE team_name IS NULL");

$dbh->bz_commit_transaction();
