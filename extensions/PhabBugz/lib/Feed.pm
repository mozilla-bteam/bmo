# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Feed;

use 5.10.1;

use Moo;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Revision;
use Bugzilla::Extension::PhabBugz::Util qw(
    add_security_sync_comments
    create_revision_attachment
    create_private_revision_policy
    edit_revision_policy
    get_bug_role_phids
    get_members_by_phid
    make_revision_public
    request
    get_security_sync_groups
);

has 'is_daemon' => ( is => 'rw', default => 0 );
has 'logger'    => ( is => 'rw' );

sub start {
    my ($self) = @_;
    while (1) {
        if (Bugzilla->params->{phabricator_enabled}) {
            $self->feed_query();
        }
        sleep(PHAB_POLL_SECONDS);
        Bugzilla->_cleanup();
    }
}

sub feed_query {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    # Ensure Phabricator syncing is enabled
    if (!Bugzilla->params->{phabricator_enabled}) {
        $self->logger->info("PHABRICATOR SYNC DISABLED");
        return;
    }

    $self->logger->info("FEED: Fetching new transactions");

    my $last_ts = $dbh->selectrow_array("
        SELECT value FROM phabbugz WHERE name = 'feed_last_ts'");
    $last_ts ||= 0;
    $self->logger->debug("LAST_TS: $last_ts");

    # Check for new transctions (stories)
    my $transactions = $self->feed_transactions($last_ts);
    if (!$transactions) {
        $self->logger->info("FEED: No new transactions");
        return;
    }

    # Process each story
    foreach my $story (keys %$transactions) {
        my $skip = 0;

        $self->logger->debug("STORY: $story");
        my $story_data = $transactions->{$story};
        my $object_phid = $story_data->{objectPHID};
        $self->logger->debug("OBJECT: $object_phid");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            $self->logger->debug("SKIP: Not a revision change");
            $skip = 1;
        }

        # Skip changes done by phab-bot user
        my $userids = get_members_by_phid([$story_data->{authorPHID}]);
        if (@$userids) {
            my $user = Bugzilla::User->new({ id => $userids->[0], cache => 1 });
            $skip = 1 if $user->login eq PHAB_AUTOMATION_USER;
        }

        if (!$skip) {
            my $revision = Bugzilla::Extension::PhabBugz::Revision->new({ phids => [$object_phid] });
            $self->process_revision_change($revision, $story_data->{text});
        }

        # Store the largest last epoch so we can start from there in the next session
        $self->logger->debug("UPDATING LAST_TS: $last_ts");
        $dbh->do("REPLACE INTO phabbugz (name, value) VALUES ('feed_last_ts', ?)",
                 undef, $story_data->{epoch}+1);
    }
}

sub process_revision_change {
    my ($self, $revision, $story_text) = @_;

    Bugzilla->set_user(Bugzilla::User->new({ name => PHAB_AUTOMATION_USER }));

    my $revision_id    = $revision->id;
    my $revision_phid  = $revision->phid;
    my $revision_title = $revision->title || 'Unknown Description';
    my $bug_id         = $revision->bug_id;

    $self->logger->info("REVISION CHANGE FOUND: D$revision_id: $revision_title | bug: $bug_id | $story_text");

    my $bug = Bugzilla::Bug->new($bug_id);

    # If bug is public then remove privacy policy
    my $result;
    if (!@{ $bug->groups_in }) {
        $result = make_revision_public($revision_id);
    }
    # else bug is private
    else {
        my @set_groups = get_security_sync_groups($bug);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            add_security_sync_comments([$revision], $bug);
        }

        my $policy_phid = create_private_revision_policy($bug, \@set_groups);
        my $subscribers = get_bug_role_phids($bug);
        $result = edit_revision_policy($revision_phid, $policy_phid, $subscribers);
    }

    my $attachment = create_revision_attachment($bug, $revision_id, $revision_title);

    Bugzilla::BugMail::Send($bug_id, { changer => Bugzilla->user });

    $self->logger->info("SUCCESS");
}

sub feed_transactions {
    my ($self, $epoch) = @_;
    my $data = { view => 'text' };
    $data->{epochStart} = $epoch if $epoch;
    my $result = request('feed.query_epoch', $data);
    # Stupid conduit. If the feed results are empty it returns
    # an empty list ([]). If there is data it returns it in a
    # hash ({}) so we have adjust to be consistent.
    return ref $result->{result} eq 'HASH' ? $result->{result} : {};
}

1;
