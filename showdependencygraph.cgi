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
use Bugzilla::Util qw(detaint_natural mermaid_quote truncate_string);

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
$cgi->param('id') || ThrowCodeError('missing_bug_id');
my $bug = Bugzilla::Bug->check($cgi->param('id'));

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

my $urlbase        = Bugzilla->localconfig->urlbase;
my %seen           = ();
my %edgesdone      = ();
my %bug_class_seen = ();

my $add_link = sub {
  my ($blocked, $dependson) = @_;
  $dependson ||= 0;
  my $link_text = '';

  # my ($dependson_status, $dependson_resolution, $dependson_summary);

  state $sth = $dbh->prepare(
    q{SELECT bug_status, resolution, short_desc
        FROM bugs
       WHERE bugs.bug_id = ?}
  );

  my $key = "$blocked,$dependson";
  if (!exists $edgesdone{$key}) {
    if ($dependson) {

      # ($dependson_status, $dependson_resolution, $dependson_summary)
      #   = $dbh->selectrow_array($sth, undef, $dependson);

      $link_text .= $dependson;

      # $link_text .= ($dependson_status eq 'RESOLVED') ? '[' : '([';
      # $link_text .= "$dependson";

   # if ($show_summary && $user->can_see_bug($dependson)) {
   #   $dependson_summary = truncate_string($dependson_summary, 80, '...');
   #   $dependson_summary = mermaid_quote($dependson_summary);
   #   $link_text .= "<br>$dependson_status $dependson_resolution $dependson_summary";
   # }
   #
   # $link_text .= ($dependson_status eq 'RESOLVED') ? ']' : '])';

      $link_text .= ' --> ';
    }

    # my ($blocked_status, $blocked_resolution, $blocked_summary)
    #   = $dbh->selectrow_array($sth, undef, $blocked);

    $link_text .= $blocked;

    # $link_text .= ($blocked_status eq 'RESOLVED') ? '[' : '([';
    # $link_text .= "$blocked";
    #
    # if ($show_summary && $user->can_see_bug($blocked)) {
    #   $blocked_summary = truncate_string($blocked_summary, 80, '...');
    #   $blocked_summary = mermaid_quote($blocked_summary);
    #   $link_text .= "<br>$blocked_status $blocked_resolution $blocked_summary";
    # }
    #
    # $link_text .= ($blocked_status eq 'RESOLVED') ? ']' : '])';

    $link_text .= "\n";

    if ($dependson && !$seen{$dependson}) {

      # $link_text
      #   .= ($dependson_status eq 'RESOLVED')
      #   ? "class $dependson resolved\n"
      #   : "class $dependson open\n";
      #
      # # Display additional styling if this is the base bug id
      # if ($dependson == $bug->id) {
      #   $link_text .= "class $dependson base\n";
      # }

      $link_text .= qq{click $dependson "${urlbase}show_bug.cgi?id=$dependson"\n};
    }

    if (!$seen{$blocked}) {

      # $link_text
      #   .= ($blocked_status eq 'RESOLVED')
      #   ? "class $blocked resolved\n"
      #   : "class $blocked open\n";
      #
      # # Display additional styling if this is the base bug id
      # if ($blocked == $bug->id) {
      #   $link_text .= "class $blocked base\n";
      # }

      $link_text .= qq{click $blocked "${urlbase}show_bug.cgi?id=$blocked"\n};
    }

    $edgesdone{$key}  = 1;
    $seen{$blocked}   = 1;
    $seen{$dependson} = 1 if $dependson;
  }

  return $link_text;
};

# Start the graph
my $graph = "graph $rankdir
classDef resolved fill:#f96,stroke:#333,stroke-width:2px;
classDef open fill:#9f6,stroke:#333,stroke-width:2px;
classDef base stroke-width:5px\n";

my @stack = ($bug->id);

if ($display eq 'web') {
  my $sth = $dbh->prepare(
    q{SELECT blocked, dependson
        FROM dependencies
       WHERE blocked = ? OR dependson = ?}
  );

  foreach my $id (@stack) {
    my $dependencies = $dbh->selectall_arrayref($sth, undef, ($id, $id));

    # Show a single node if no dependencies instead of a blank graph
    if (!@{$dependencies}) {
      $graph .= $add_link->($id);
    }
    else {
      foreach my $dependency (@{$dependencies}) {
        my ($blocked, $dependson) = @{$dependency};
        if ( $blocked != $id
          && !exists $seen{$blocked}
          && scalar @stack < MAX_DEP_GRAPH_BUGS)
        {
          push @stack, $blocked;
        }
        if ( $dependson != $id
          && !exists $seen{$dependson}
          && scalar @stack < MAX_DEP_GRAPH_BUGS)
        {
          push @stack, $dependson;
        }
        $graph .= $add_link->($blocked, $dependson);
      }
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

    # Show a single node if no dependencies instead of a blank graph
    if (!@{$blocker_ids}) {
      $graph .= $add_link->($id);
    }
    else {
      foreach my $blocker_id (@{$blocker_ids}) {
        if (!exists $seen{$blocker_id} && scalar @blocker_stack < MAX_DEP_GRAPH_BUGS) {
          push @blocker_stack, $blocker_id;
        }
        $graph .= $add_link->($id, $blocker_id);
      }
    }
  }
  my @dependent_stack = @stack;
  foreach my $id (@dependent_stack) {
    my $dep_bug_ids
      = Bugzilla::Bug::list_relationship('dependencies', 'dependson', 'blocked',
      $id);
    foreach my $dep_bug_id (@{$dep_bug_ids}) {
      if (!exists $seen{$dep_bug_id} && scalar @dependent_stack < MAX_DEP_GRAPH_BUGS)
      {
        push @dependent_stack, $dep_bug_id;
      }
      $graph .= $add_link->($dep_bug_id, $id);
    }
  }
}

$vars->{'graph_data'} = $graph;

# Make sure we only include valid integers (protects us from XSS attacks).
my @bugs = grep { detaint_natural($_) } split /[\s,]+/, $cgi->param('id');
$vars->{'bug_id'}      = join ', ', @bugs;
$vars->{'display'}     = $display;
$vars->{'rankdir'}     = $rankdir;
$vars->{'showsummary'} = $cgi->param('showsummary');
$vars->{'debug'}       = ($cgi->param('debug') ? 1 : 0);
$vars->{'graph_size'}  = (length $graph) + 1000;

if (scalar keys %seen > MAX_DEP_GRAPH_BUGS) {
  $vars->{'graph_too_large'} = 1;
}

# Generate and return the UI (HTML page) from the appropriate template.
print $cgi->header();
$template->process('bug/dependency-graph.html.tmpl', $vars)
  || ThrowTemplateError($template->error());
