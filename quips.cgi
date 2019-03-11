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
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Token;

my $user = Bugzilla->login(LOGIN_REQUIRED);

my $cgi      = Bugzilla->cgi;
my $dbh      = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars     = {};

my $action = $cgi->param('action') || "";
my $token = $cgi->param('token');

if ($action eq "show") {

  # Read in the entire quip list
  my $quipsref = $dbh->selectall_arrayref(
    "SELECT quipid, userid, quip, approved FROM quips");

  my $quips;
  my @quipids;
  foreach my $quipref (@$quipsref) {
    my ($quipid, $userid, $quip, $approved) = @$quipref;
    $quips->{$quipid}
      = {'userid' => $userid, 'quip' => $quip, 'approved' => $approved};
    push(@quipids, $quipid);
  }

  my $users;
  my $sth = $dbh->prepare("SELECT login_name FROM profiles WHERE userid = ?");
  foreach my $quipid (@quipids) {
    my $userid = $quips->{$quipid}{'userid'};
    if ($userid && not defined $users->{$userid}) {
      ($users->{$userid}) = $dbh->selectrow_array($sth, undef, $userid);
    }
  }
  $vars->{'quipids'}    = \@quipids;
  $vars->{'quips'}      = $quips;
  $vars->{'users'}      = $users;
  $vars->{'show_quips'} = 1;
}

if ($action eq "add") {
  (Bugzilla->params->{'quip_list_entry_control'} eq "closed")
    && ThrowUserError("no_new_quips");

  check_hash_token($token, ['create-quips']);

  # Add the quip
  # Upstreaming: https://bugzilla.mozilla.org/show_bug.cgi?id=621879
  my $approved
    = (Bugzilla->params->{'quip_list_entry_control'} eq "open")
    || $user->in_group('bz_quip_moderators')
    || 0;
  my $comment = $cgi->param("quip");
  $comment || ThrowUserError("need_quip");

  $dbh->do("INSERT INTO quips (userid, quip, approved) VALUES (?, ?, ?)",
    undef, ($user->id, $comment, $approved));

  $vars->{'added_quip'} = $comment;
}

if ($action eq 'approve') {
  $user->in_group('bz_quip_moderators')
    || ThrowUserError("auth_failure",
    {group => "bz_quip_moderators", action => "approve", object => "quips"});

  check_hash_token($token, ['approve-quips']);

  # Read in the entire quip list
  my $quipsref = $dbh->selectall_arrayref("SELECT quipid, approved FROM quips");

  my %quips;
  foreach my $quipref (@$quipsref) {
    my ($quipid, $approved) = @$quipref;
    $quips{$quipid} = $approved;
  }

  my @approved;
  my @unapproved;
  foreach my $quipid (keys %quips) {

    # Must check for each quipid being defined for concurrency and
    # automated usage where only one quipid might be defined.
    my $quip = $cgi->param("quipid_$quipid") ? 1 : 0;
    if (defined($cgi->param("defined_quipid_$quipid"))) {
      if ($quips{$quipid} != $quip) {
        if ($quip) {
          push(@approved, $quipid);
        }
        else {
          push(@unapproved, $quipid);
        }
      }
    }
  }
  $dbh->do(
    "UPDATE quips SET approved = 1 WHERE quipid IN (" . join(",", @approved) . ")")
    if ($#approved > -1);
  $dbh->do("UPDATE quips SET approved = 0 WHERE quipid IN ("
      . join(",", @unapproved) . ")")
    if ($#unapproved > -1);
  $vars->{'approved'}   = \@approved;
  $vars->{'unapproved'} = \@unapproved;
}

if ($action eq "delete") {
  $user->in_group('bz_quip_moderators')
    || ThrowUserError("auth_failure",
    {group => "bz_quip_moderators", action => "delete", object => "quips"});
  my $quipid = $cgi->param("quipid");
  ThrowCodeError("need_quipid") unless $quipid =~ /(\d+)/;
  $quipid = $1;
  check_hash_token($token, ['quips', $quipid]);

  ($vars->{'deleted_quip'})
    = $dbh->selectrow_array("SELECT quip FROM quips WHERE quipid = ?",
    undef, $quipid);
  $dbh->do("DELETE FROM quips WHERE quipid = ?", undef, $quipid);
}

print $cgi->header();
$template->process("list/quips.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
