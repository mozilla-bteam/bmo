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
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural);

use List::Util qw(none);

Bugzilla->login(LOGIN_REQUIRED);

my $user     = Bugzilla->user;
my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

# Connect to the shadow database if this installation is using one to improve
# performance.
my $dbh = Bugzilla->switch_to_shadow_db();

# Initial sanity checks
my $bug_id = $cgi->param('id');
$bug_id || ThrowCodeError('missing_bug_id');

# Make sure the submitted 'rankdir' value is valid.
my @valid_rankdirs = qw(LR RL TB BT);
my $rankdir        = $cgi->param('rankdir') || 'TB';
if (none { $_ eq $rankdir } @valid_rankdirs) {
  $rankdir = 'TB';
}

# Make sure the submitted 'display' value is valid.
my @valid_displays = qw(tree web);
my $display        = $cgi->param('display') || 'tree';
if (none { $_ eq $display } @valid_displays) {
  $display = 'tree';
}

my $show_summary = $cgi->param('showsummary');

my %seen      = ();
my %edgesdone = ();
my $bug_count = 0;

my $add_link = sub {
  my ($blocked, $dependson) = @_;
  my $link_text = '';

  state $sth = $dbh->prepare(
    q{SELECT bug_status, resolution, short_desc
        FROM bugs
       WHERE bugs.bug_id = ?}
  );

  my $key = "$blocked,$dependson";
  if (!exists $edgesdone{$key}) {

    my ($dependson_status, $dependson_resolution, $dependson_summary)
      = $dbh->selectrow_array($sth, undef, $dependson);

    my ($blocked_status, $blocked_resolution, $blocked_summary)
      = $dbh->selectrow_array($sth, undef, $blocked);

    $link_text .= $dependson;
    $link_text .= ($dependson_status eq 'RESOLVED') ? '[' : '([';
    $link_text .= "$dependson";

    if ($show_summary && $user->can_see_bug($dependson)) {
      $link_text .= "<br>$dependson_status $dependson_resolution $dependson_summary";
    }

    $link_text .= ($dependson_status eq 'RESOLVED') ? ']' : '])';

    $link_text .= ' --> ';

    $link_text .= $blocked;
    $link_text .= ($blocked_status eq 'RESOLVED') ? '[' : '([';
    $link_text .= "$blocked";

    if ($show_summary && $user->can_see_bug($blocked)) {
      $link_text .= "<br>$blocked_status $blocked_resolution $blocked_summary";
    }

    $link_text .= ($blocked_status eq 'RESOLVED') ? ']' : '])';

    $link_text .= "\n";

    $link_text
      .= ($dependson_status eq 'RESOLVED')
      ? "class $dependson resolved\n"
      : "class $dependson open\n";
    $link_text
      .= ($blocked_status eq 'RESOLVED')
      ? "class $blocked resolved\n"
      : "class $blocked open\n";

    $bug_count++;
    $edgesdone{$key}  = 1;
    $seen{$blocked}   = 1;
    $seen{$dependson} = 1;
  }

  return $link_text;
};

# Start the graph
my $graph = "graph $rankdir
classDef resolved fill:#f96,stroke:#333,stroke-width:2px;
classDef open fill:#9f6,stroke:#333,stroke-width:2px;\n";

my %baselist;
foreach my $i (split /[\s,]+/, $cgi->param('id')) {
  my $bug = Bugzilla::Bug->check($i);
  $baselist{$bug->id} = 1;
}

my @stack = keys %baselist;

if ($display eq 'web') {
  my $sth = $dbh->prepare(
    q{SELECT blocked, dependson
        FROM dependencies
       WHERE blocked = ? OR dependson = ?}
  );

  foreach my $id (@stack) {
    my $dependencies = $dbh->selectall_arrayref($sth, undef, ($id, $id));
    foreach my $dependency (@{$dependencies}) {
      my ($blocked, $dependson) = @{$dependency};
      if ($blocked != $id && !exists $seen{$blocked}) {
        push @stack, $blocked;
      }
      if ($dependson != $id && !exists $seen{$dependson}) {
        push @stack, $dependson;
      }
      $graph .= $add_link->($blocked, $dependson);
    }
  }
}

# This is the default: a tree instead of a spider web.
else {
  my @blocker_stack = @stack;
  foreach my $id (@blocker_stack) {
    my $blocker_ids
      = Bugzilla::Bug::list_relationship('dependencies', 'blocked', 'dependson',
      $id);
    foreach my $blocker_id (@{$blocker_ids}) {
      push @blocker_stack, $blocker_id unless $seen{$blocker_id};
      $graph .= $add_link->($id, $blocker_id);
    }
  }
  my @dependent_stack = @stack;
  foreach my $id (@dependent_stack) {
    my $dep_bug_ids
      = Bugzilla::Bug::list_relationship('dependencies', 'dependson', 'blocked',
      $id);
    foreach my $dep_bug_id (@{$dep_bug_ids}) {
      push @dependent_stack, $dep_bug_id unless $seen{$dep_bug_id};
      $graph .= $add_link->($dep_bug_id, $id);
    }
  }
}

foreach my $k (keys %baselist) {
  $seen{$k} = 1;
}

my $urlbase = Bugzilla->localconfig->urlbase;
foreach my $k (keys %seen) {
  $graph .= qq{click $k "${urlbase}show_bug.cgi?id=$k"\n};
}

$vars->{'graph_data'} = $graph;

if ($bug_count > MAX_DEP_GRAPH_BUGS) {
  ThrowUserError('dep_graph_too_large');
}

# Make sure we only include valid integers (protects us from XSS attacks).
my @bugs = grep { detaint_natural($_) } split /[\s,]+/, $cgi->param('id');
$vars->{'bug_id'}        = join ', ', @bugs;
$vars->{'multiple_bugs'} = ($cgi->param('id') =~ /[ ,]/);
$vars->{'display'}       = $display;
$vars->{'rankdir'}       = $rankdir;
$vars->{'showsummary'}   = $cgi->param('showsummary');
$vars->{'debug'}         = ($cgi->param('debug') ? 1 : 0);

# Generate and return the UI (HTML page) from the appropriate template.
print $cgi->header();
$template->process('bug/dependency-graph.html.tmpl', $vars)
  || ThrowTemplateError($template->error());
