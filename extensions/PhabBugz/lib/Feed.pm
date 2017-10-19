# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Feed;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    $self->{is_daemon} = 0;
    return $self;
}

sub is_daemon {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{is_daemon} = $value ? 1 : 0;
    }
    return $self->{is_daemon};
}

sub logger {
    my ($self, $value) = @_;
    $self->{logger} = $value if $value;
    return $self->{logger};
}

sub start {
    my ($self) = @_;
    while(1) {
        if ($self->_dbh_check()) {
            $self->feed_query();
        }
        sleep(PHAB_POLL_SECONDS);
    }
}

sub feed_query {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    $self->logger->info("FEED: Polling");

    my $last_ts = $dbh->selectrow_array("
        SELECT value FROM phabbugz WHERE name = 'feed_last_ts'");

    # Check for new transctions (stories)
    my $transactions = get_feed_transactions($last_ts+1);
    if (!$transactions) {
        $self->logger->info("FEED: No new transactions");
        return;
    }

    # Process each story
    foreach my $story (keys %$transactions) {
        $self->logger->info("STORY: $story");
        my $story_data = $transactions->{$story};
        my $object_phid = $story_data->{objectPHID};
        $self->logger->info("OBJECT: $object_phid");
        if ($object_phid !~ /^PHID-DREV/) {
            $self->logger->info("SKIP: Not a revision change");
            next;
        }
        my ($revision) = get_revisions_by_phids([$object_phid]);
        $self->logger->info("REVSION: " . $revision->{'id'} . ": " .
                            $revision->{'fields'}->{'title'} . " " .
                            $revision->{'fields'}->{'bugzilla.bug-id'} . " " .
                            $story_data->{'text'});

        # Find the highest epoch for storage in feed_last_ts
        if ($story_data->{epoch} > $last_ts) {
            $last_ts = $story_data->{epoch};
        }
    }

    $self->logger->debug("LAST_TS: $last_ts");
    $dbh->do("REPLACE INTO phabbugz (name, value) VALUES ('feed_last_ts', ?)",
             undef, $last_ts);
}

sub _dbh_check {
    my ($self) = @_;
    eval {
        Bugzilla->dbh->selectrow_array("SELECT 1 FROM phabbugz");
    };
    if ($@) {
        return 0;
    } else {
        return 1;
    }
}

1;
