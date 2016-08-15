#!/usr/bin/perl -w
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is the Mozilla
# Corporation. Portions created by Mozilla are
# Copyright (C) 2006 Mozilla Foundation. All Rights Reserved.
#
# Contributor(s): Myk Melez <myk@mozilla.org>
#                 Alex Brugh <alex@cs.umn.edu>
#                 Dave Miller <justdave@mozilla.com>
#                 Byron Jones <glob@mozilla.com>

use strict;

use FindBin qw($RealBin);
use lib ("$RealBin/..", "$RealBin/../lib", "$RealBin/../local/lib/perl5");

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Hook;
use Bugzilla::Util;
use Getopt::Long;
use List::MoreUtils qw(uniq);
$| = 1;

my $dbh = Bugzilla->dbh;

# This SQL is designed to sanitize a copy of a Bugzilla database so that it
# doesn't contain any information that can't be viewed from a web browser by
# a user who is not logged in.

my ($dry_run, $from_cron, $keep_attachments, $keep_group_bugs, $keep_groups, $execute,
    $keep_passwords, $keep_insider, $trace, $enable_email) = (0, 0, 0, '', 0, 0, 0, 0, 0, 0);
my $keep_group_bugs_sql = '';

my $syntax = <<EOF;
options:
--execute          perform database sanitization
--keep-attachments disable removal of attachment content
--keep-passwords   disable resetting of passwords
--keep-insider     disable removal of insider comments and attachments
--keep-group-bugs  disable removal of the specified groups and associated bugs
--keep-groups      disable removal of group definitions
--enable-email     do not disable email for all users
--dry-run          do not update the database, just output what will be deleted
--from-cron        quite mode - suppress non-warning/error output
--trace            output sql statements
EOF
GetOptions(
    "execute" => \$execute,
    "dry-run" => \$dry_run,
    "from-cron" => \$from_cron,
    "keep-attachments" => \$keep_attachments,
    "keep-passwords" => \$keep_passwords,
    "keep-insider" => \$keep_insider,
    "keep-group-bugs:s" => \$keep_group_bugs,
    "keep-groups" => \$keep_groups,
    "trace" => \$trace,
    "enable-email" => \$enable_email,
) or die $syntax;
die "--execute switch required to perform database sanitization.\n\n$syntax"
    unless $execute or $dry_run;

if ($keep_group_bugs ne '') {
    my @groups;
    foreach my $group_id (split(/\s*,\s*/, $keep_group_bugs)) {
        my $group;
        if ($group_id =~ /\D/) {
            $group = Bugzilla::Group->new({ name => $group_id });
        } else {
            $group = Bugzilla::Group->new($group_id);
        }
        die "Invalid group '$group_id'\n" unless $group;
        push @groups, $group->id;
    }
    $keep_group_bugs_sql = "NOT IN (" . join(",", @groups) . ")";
}

$dbh->{TraceLevel} = 1 if $trace;

if ($dry_run) {
    print "** dry run : no changes to the database will be made **\n";
    $dbh->bz_start_transaction();
}
eval {
    delete_non_public_products();
    delete_secure_bugs();
    delete_deleted_comments();
    delete_insider_comments() unless $keep_insider;
    delete_security_groups() unless $keep_groups;
    delete_sensitive_user_data();
    delete_attachment_data() unless $keep_attachments;
    delete_bug_user_last_visit();
    delete_user_request_log();
    Bugzilla::Hook::process('db_sanitize');
    disable_email_delivery() unless $enable_email;
    print "All done!\n";
    $dbh->bz_rollback_transaction() if $dry_run;
};
if ($@) {
    $dbh->bz_rollback_transaction() if $dry_run;
    die "$@" if $@;
}

sub delete_non_public_products {
    # Delete all non-public products, and all data associated with them
    my @products = Bugzilla::Product->get_all();
    my $mandatory = CONTROLMAPMANDATORY;
    foreach my $product (@products) {
        # if there are any mandatory groups on the product, nuke it and
        # everything associated with it (including the bugs)
        Bugzilla->params->{'allowbugdeletion'} = 1; # override this in memory for now
        my $mandatorygroups = $dbh->selectcol_arrayref("SELECT group_id FROM group_control_map WHERE product_id = ? AND (membercontrol = $mandatory)", undef, $product->id);
        if (0 < scalar(@$mandatorygroups)) {
            print "Deleting product '" . $product->name . "'...\n";
            $product->remove_from_db();
        }
    }
}

sub delete_secure_bugs {
    # Delete all data for bugs in security groups.
    my $buglist = $dbh->selectall_arrayref(
        $keep_group_bugs
        ? "SELECT DISTINCT bug_id FROM bug_group_map WHERE group_id $keep_group_bugs_sql"
        : "SELECT DISTINCT bug_id FROM bug_group_map"
    );
    my $numbugs = scalar(@$buglist);
    my $bugnum = 0;
    print "Deleting $numbugs bugs in " . ($keep_group_bugs ? 'non-' : '') . "security groups...\n";
    foreach my $row (@$buglist) {
        my $bug_id = $row->[0];
        $bugnum++;
        print "\r$bugnum/$numbugs" unless $from_cron;
        my $bug = new Bugzilla::Bug($bug_id);
        $bug->remove_from_db();
    }
    print "\rDone            \n" unless $from_cron;
}

sub delete_deleted_comments {
    # Delete all comments tagged as 'deleted'
    my $comment_ids = $dbh->selectcol_arrayref("SELECT comment_id FROM longdescs_tags WHERE tag='deleted'");
    return unless @$comment_ids;
    print "Deleting 'deleted' comments...\n";
    my @bug_ids = uniq @{
        $dbh->selectcol_arrayref("SELECT bug_id FROM longdescs WHERE comment_id IN (" . join(',', @$comment_ids) . ")")
    };
    $dbh->do("DELETE FROM longdescs WHERE comment_id IN (" . join(',', @$comment_ids) . ")");
    foreach my $bug_id (@bug_ids) {
        Bugzilla::Bug->new($bug_id)->_sync_fulltext(update_comments => 1);
    }
}

sub delete_insider_comments {
    # Delete all 'insidergroup' comments and attachments
    print "Deleting 'insidergroup' comments and attachments...\n";
    $dbh->do("DELETE FROM longdescs WHERE isprivate = 1");
    $dbh->do("DELETE attach_data FROM attachments JOIN attach_data ON attachments.attach_id = attach_data.id WHERE attachments.isprivate = 1");
    $dbh->do("DELETE FROM attachments WHERE isprivate = 1");
    $dbh->do("UPDATE bugs_fulltext SET comments = comments_noprivate");
}

sub delete_security_groups {
    # Delete all security groups.
    print "Deleting " . ($keep_group_bugs ? 'non-' : '') . "security groups...\n";
    $dbh->do("DELETE user_group_map FROM groups JOIN user_group_map ON groups.id = user_group_map.group_id WHERE groups.isbuggroup = 1");
    $dbh->do("DELETE group_group_map FROM groups JOIN group_group_map ON (groups.id = group_group_map.member_id OR groups.id = group_group_map.grantor_id) WHERE groups.isbuggroup = 1");
    $dbh->do("DELETE group_control_map FROM groups JOIN group_control_map ON groups.id = group_control_map.group_id WHERE groups.isbuggroup = 1");
    $dbh->do("UPDATE flagtypes LEFT JOIN groups ON flagtypes.grant_group_id = groups.id SET grant_group_id = NULL WHERE groups.isbuggroup = 1");
    $dbh->do("UPDATE flagtypes LEFT JOIN groups ON flagtypes.request_group_id = groups.id SET request_group_id = NULL WHERE groups.isbuggroup = 1");
    if ($keep_group_bugs) {
        $dbh->do("DELETE FROM groups WHERE isbuggroup = 1 AND id $keep_group_bugs_sql");
    } else {
        $dbh->do("DELETE FROM groups WHERE isbuggroup = 1");
    }
}

sub delete_sensitive_user_data {
    # Remove sensitive user account data.
    print "Deleting sensitive user account data...\n";
    $dbh->do("UPDATE profiles SET cryptpassword = 'deleted'") unless $keep_passwords;
    $dbh->do("DELETE FROM user_api_keys");
    $dbh->do("DELETE FROM profiles_activity");
    $dbh->do("DELETE FROM profile_search");
    $dbh->do("DELETE FROM profile_mfa");
    $dbh->do("DELETE FROM namedqueries");
    $dbh->do("DELETE FROM tokens");
    $dbh->do("DELETE FROM logincookies");
    $dbh->do("DELETE FROM login_failure");
    $dbh->do("DELETE FROM audit_log");
    # queued bugmail
    $dbh->do("DELETE FROM ts_error");
    $dbh->do("DELETE FROM ts_exitstatus");
    $dbh->do("DELETE FROM ts_funcmap");
    $dbh->do("DELETE FROM ts_job");
    $dbh->do("DELETE FROM ts_note");
}

sub delete_attachment_data {
    # Delete unnecessary attachment data.
    print "Removing attachment data...\n";
    $dbh->do("UPDATE attach_data SET thedata = ''");
    $dbh->do("UPDATE attachments SET attach_size = 0");
}

sub delete_bug_user_last_visit {
    print "Removing all entries from bug_user_last_visit...\n";
    $dbh->do('TRUNCATE TABLE bug_user_last_visit');
}

sub delete_user_request_log {
    print "Removing all entries from user_request_log...\n";
    $dbh->do('TRUNCATE TABLE user_request_log');
}

sub disable_email_delivery {
    # turn off email delivery for all users.
    print "Turning off email delivery...\n";
    $dbh->do("UPDATE profiles SET disable_mail = 1");

    # Also clear out the default flag cc as well since they do not
    # have to be in the profiles table
    $dbh->do("UPDATE flagtypes SET cc_list = NULL");
}
