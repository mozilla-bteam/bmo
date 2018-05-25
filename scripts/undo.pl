#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile catdir rel2abs);
use Cwd qw(realpath);
BEGIN {
    require lib;
    my $dir = rel2abs(catdir(dirname(__FILE__), '..'));
    lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}

use Bugzilla;
BEGIN { Bugzilla->extensions };

use Try::Tiny;

my @triage_owners = ('MattN+bmo@mozilla.com');

foreach my $triage_owner (@triage_owners) {
    undo(
        changes => [
            q{ resolution = 'INACTIVE' AND triage_owner.login_name = ? },
            $triage_owner,
        ],
        comments => [
            q{ resolution = 'INACTIVE' AND triage_owner.login_name = ? },
            $triage_owner,
        ]
    );
}

sub undo {
    my %param = @_;
    my $changes = get_changes(@{ $param{changes} });
    my $comments = get_comments(@{ $param{comments} });

    my %action;
    while ($_ = $changes->()) {
        push @{ $action{$_->{bug_id}}{$_->{bug_when}}{remove_activities} }, { id => $_->{change_id} };
        $action{ $_->{bug_id} }{ $_->{bug_when} }{change}{ $_->{field_name} } = {
            replace => $_->{added},
            with    => $_->{removed},
        };
    }

    while ($_ = $comments->()) {
        push @{ $action{ $_->{bug_id} }{$_->{bug_when}}{remove_comments} }, {
            id => $_->{comment_id},
        };
    }

    my $dbh = Bugzilla->dbh;
    foreach my $bug_id (keys %action) {
        $dbh->bz_start_transaction;
        try {
            my ($delta_ts, $lastdiffed) = $dbh->selectrow_array(
                'SELECT delta_ts, lastdiffed FROM bugs where bug_id = ?',
                undef,
                $bug_id);
            my $action = delete $action{$bug_id}{$delta_ts};
            if (keys %{ $action{$bug_id}{$delta_ts}}) {
                die "skipping because more than one change\n";
            }
            elsif (!$action) {
                die "skipping because most recent change newer than automation change\n";
            }
            foreach my $field (keys %{ $action->{change} }) {
                my $change = $action->{change}{$field};
                $dbh->do("UPDATE bugs SET $field = ? WHERE bug_id = ? AND $field = ?",
                    undef, $change->{with}, $bug_id, $change->{replace})
                    or die "Failed to set $field to $change->{with}";
            }
            $dbh->bz_commit_transaction;
        } catch {
            warn "Error updating $bug_id: $_";
            $dbh->bz_rollback_transaction;
        };
    }
}

sub get_changes {
    my ($where, @bind) = @_;

    my $sql = qq{
        SELECT
            BA.id AS change_id,
            BA.bug_id,
            FD.name field_name,
            BA.removed,
            BA.added,
            BA.bug_when
        FROM
            bugs_activity AS BA
                JOIN
            fielddefs AS FD ON BA.fieldid = FD.id
                JOIN
            profiles AS changer ON changer.userid = BA.who
                JOIN
            (SELECT
                bug_id
            FROM
                bugs
            JOIN products AS product ON product.id = product_id
            JOIN components AS component ON component.id = component_id
            LEFT JOIN profiles AS triage_owner ON triage_owner.userid = component.triage_owner_id
            WHERE
                $where
            ) target_bugs ON BA.bug_id = target_bugs.bug_id
        WHERE
            changer.login_name = 'automation\@bmo.tld'
                AND BA.bug_when BETWEEN '2018-05-22' AND '2018-05-24'
    };
    my $sth = Bugzilla->dbh->prepare($sql);
    $sth->execute(@bind);

    return sub { $sth->fetchrow_hashref };
}

sub get_comments {
    my ($where, @bind) = @_;

    my $sql = qq{
        SELECT
            C.comment_id AS comment_id,
            C.bug_id AS bug_id,
            C.bug_when
        FROM
            longdescs AS C
                JOIN
            profiles AS commenter ON commenter.userid = C.who
                JOIN
            (SELECT
                bug_id
            FROM
                bugs
            JOIN products AS product ON product.id = product_id
            JOIN components AS component ON component.id = component_id
            LEFT JOIN profiles AS triage_owner ON triage_owner.userid = component.triage_owner_id
            WHERE
                $where
            ) target_bugs ON C.bug_id = target_bugs.bug_id
        WHERE
            commenter.login_name = 'automation\@bmo.tld'
                AND C.bug_when BETWEEN '2018-05-22' AND '2018-05-24'
    };
    my $sth = Bugzilla->dbh->prepare($sql);
    $sth->execute(@bind);

    return sub { $sth->fetchrow_hashref };
}