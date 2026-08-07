#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##############################################################
# Test for the edit_count and last_change_time comment fields #
# GET /rest/bug/<id>/comment                                  #
# GET /rest/bug/comment/<comment_id>                          #
##############################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Bugzilla;
use List::Util     qw(first);
use QA::Util       qw(get_config);
use QA::REST::Util qw(api_headers);

use Test::Mojo;
use Test::More;

# REST returns dates in ISO-8601 (with a trailing Z).
use constant DATETIME_REGEX => qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ?$/;

my $config = get_config();
my $url    = Bugzilla->localconfig->urlbase;

# edit_comments_group defaults to 'editbugs' and edit_comments_admins_group
# defaults to 'admin', so these three users cover all three visibility cases.
my $admin_key        = $config->{admin_user_api_key};
my $editbugs_key     = $config->{editbugs_user_api_key};
my $unprivileged_key = $config->{unprivileged_user_api_key};

my $t = Test::Mojo->new();
$t->ua->max_redirects(1);

###################################
# Create the comments to be edited #
###################################

sub add_comment {
  my ($text) = @_;
  $t->post_ok($url
      . 'rest/bug/public_bug/comment' => {'X-Bugzilla-API-Key' => $editbugs_key} =>
      json                            => {comment => $text})->status_is(201);
  return $t->tx->res->json->{id};
}

my $edited_id   = add_comment('comment that will be edited');
my $unedited_id = add_comment('comment that will never be edited');

# Two visible edits by the comment's own author...
foreach my $revision (1, 2) {
  $t->put_ok($url
      . "rest/editcomments/comment/$edited_id" =>
      {'X-Bugzilla-API-Key' => $editbugs_key} => json =>
      {new_comment => "edited text, revision $revision"})->status_is(200);
}

# ...and one edit whose revision is hidden, which only an edit-comments admin
# may do.
$t->put_ok($url
    . "rest/editcomments/comment/$edited_id" =>
    {'X-Bugzilla-API-Key' => $admin_key} => json =>
    {new_comment => 'edited text, hidden revision', is_hidden => 1})
  ->status_is(200);

###############################
# GET /rest/bug/comment/<id>  #
###############################

sub get_comment {
  my ($comment_id, $api_key) = @_;
  $t->get_ok($url . "rest/bug/comment/$comment_id" => api_headers($api_key))
    ->status_is(200);
  return $t->tx->res->json->{comments}{$comment_id};
}

foreach my $case (
  {name => 'logged-out user',   key => undef},
  {name => 'unprivileged user', key => $unprivileged_key},
  )
{
  my $comment = get_comment($edited_id, $case->{key});
  ok(!exists $comment->{edit_count}, "$case->{name} does not get edit_count");
  ok(
    !exists $comment->{last_change_time},
    "$case->{name} does not get last_change_time"
  );
}

# A user who may edit others' comments sees the counts, but hidden revisions
# are not counted for them.
my $comment = get_comment($edited_id, $editbugs_key);
is($comment->{edit_count}, 2, 'editbugs user sees only the visible edits');
like($comment->{last_change_time},
  DATETIME_REGEX, 'editbugs user gets a well-formed last_change_time');

# An edit-comments admin also sees the hidden revision.
$comment = get_comment($edited_id, $admin_key);
is($comment->{edit_count}, 3, 'admin user also sees the hidden edit');
like($comment->{last_change_time},
  DATETIME_REGEX, 'admin user gets a well-formed last_change_time');

# A comment that was never edited reports zero and a null timestamp.
$comment = get_comment($unedited_id, $editbugs_key);
is($comment->{edit_count}, 0, 'unedited comment has an edit_count of 0');
ok(exists $comment->{last_change_time},
  'unedited comment still has a last_change_time key');
is($comment->{last_change_time},
  undef, 'unedited comment has a null last_change_time');

#################################
# GET /rest/bug/<id>/comment    #
#################################

# The bug-level route uses a separate code path, so check it too.
$t->get_ok($url . 'rest/bug/public_bug/comment' => api_headers($editbugs_key))
  ->status_is(200);
my $bug_comments = (values %{$t->tx->res->json->{bugs}})[0]{comments};
my $found        = first { $_->{id} == $edited_id } @$bug_comments;
ok($found, 'found the edited comment via the bug-level route');
is($found->{edit_count}, 2, 'bug-level route reports the same edit_count');
like($found->{last_change_time},
  DATETIME_REGEX, 'bug-level route reports last_change_time');

$t->get_ok(
  $url . 'rest/bug/public_bug/comment' => api_headers($unprivileged_key))
  ->status_is(200);
$bug_comments = (values %{$t->tx->res->json->{bugs}})[0]{comments};
$found        = first { $_->{id} == $edited_id } @$bug_comments;
ok(!exists $found->{edit_count},
  'bug-level route omits edit_count for unprivileged users');

done_testing();
