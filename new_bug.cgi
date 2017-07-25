#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Contributor(s): Sebastin Santy <sebastinssanty@gmail.com>
#
##############################################################################
#
# new_bug.cgi
# -------------
# Single page interface to file bugs
#
##############################################################################

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::Classification;
use Bugzilla::Keyword;
use Bugzilla::Token;
use Bugzilla::Field;
use Bugzilla::Status;
use Bugzilla::UserAgent;
use Bugzilla::BugMail;

use List::MoreUtils qw(uniq);

my $user = Bugzilla->login(LOGIN_REQUIRED);

my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

unless ($user->in_group('new-bug-testers')) {
    print $cgi->redirect(correct_urlbase());
    exit;
}

if (lc($cgi->request_method) eq 'post') {
     my $token = $cgi->param('token');
     check_hash_token($token, ['new_bug']);
     my @keywords = $cgi->param('keywords');
     my $new_bug = Bugzilla::Bug->create({
                short_desc   => scalar($cgi->param('short_desc')),
                product      => scalar($cgi->param('product')),
                component    => scalar($cgi->param('component')),
                bug_severity => 'normal',
                groups       => [],
                op_sys       => 'Unspecified',
                rep_platform => 'Unspecified',
                version      => scalar( $cgi->param('version')),
                keywords     => \@keywords,
                cc           => [],
                comment      => scalar($cgi->param('comment')),
            });
     delete_token($token);

     my $recipients = { changer => $user };
     my $bug_sent = Bugzilla::BugMail::Send($new_bug->bug_id, $recipients);
     $bug_sent->{type} = 'created';
     $bug_sent->{id}   = $new_bug->bug_id;
     my @all_mail_results = ($bug_sent);

     foreach my $dep (@{$new_bug->dependson || []}, @{$new_bug->blocked || []}) {
         my $dep_sent = Bugzilla::BugMail::Send($dep, $recipients);
         $dep_sent->{type} = 'dep';
         $dep_sent->{id}   = $dep;
         push(@all_mail_results, $dep_sent);
     }

     # Sending emails for any referenced bugs.
     foreach my $ref_bug_id (uniq @{ $new_bug->{see_also_changes} || [] }) {
         my $ref_sent = Bugzilla::BugMail::Send($ref_bug_id, $recipients);
         $ref_sent->{id} = $ref_bug_id;
         push(@all_mail_results, $ref_sent);
     }

     print $cgi->redirect(correct_urlbase() . 'show_bug.cgi?id='.$new_bug->bug_id);
} else {
 print $cgi->header();
$template->process("bug/new_bug.html.tmpl",
                    $vars)
  or ThrowTemplateError($template->error());
}

