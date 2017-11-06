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
    create_private_revision_policy
    create_revision_attachment
    edit_revision_policy
    get_bug_role_phids
    get_phab_bmo_ids
    get_security_sync_groups
    is_attachment_phab_revision
    make_revision_public
    request
    set_phab_user
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
    if (!%$transactions) {
        $self->logger->info("FEED: No new transactions");
        return;
    }

    # Process each story
    foreach my $story (keys %$transactions) {
        my $skip = 0;
        my $story_data  = $transactions->{$story};
        my $author_phid = $story_data->{authorPHID};
        my $object_phid = $story_data->{objectPHID};
        my $story_text  = $story_data->{text};
        my $story_epoch = $story_data->{epoch};

        $self->logger->debug("STORY PHID: $story");
        $self->logger->debug("STORY_EPOCH: $story_epoch");
        $self->logger->debug("AUTHOR PHID: $author_phid");
        $self->logger->debug("OBJECT PHID: $object_phid");
        $self->logger->debug("STORY TEXT: $story_text");

        # Only interested in changes to revisions for now.
        if ($object_phid !~ /^PHID-DREV/) {
            $self->logger->debug("SKIP: Not a revision change");
            $skip = 1;
        }

        # Skip changes done by phab-bot user
        my $phab_users = get_phab_bmo_ids({ phids => [$author_phid] });
        if (@$phab_users) {
            my $user = Bugzilla::User->new({ id => $phab_users->[0]->{id}, cache => 1 });
            $skip = 1 if $user->login eq PHAB_AUTOMATION_USER;
        }

        if (!$skip) {
            my $revision = Bugzilla::Extension::PhabBugz::Revision->new({ phids => [$object_phid] });
            $self->process_revision_change($revision, $story_text);
        }
        else {
            $self->logger->info('SKIPPING');
        }

        # Store the largest last epoch + 1 so we can start from there in the next session
        $story_epoch++;
        $self->logger->debug("UPDATING LAST_TS: $story_epoch");
        $dbh->do("REPLACE INTO phabbugz (name, value) VALUES ('feed_last_ts', ?)",
                 undef, $story_epoch);
    }
}

sub process_revision_change {
    my ($self, $revision, $story_text) = @_;

    # Pre setup before making changes
    my $old_user = set_phab_user();

    my $is_shadow_db = Bugzilla->is_shadow_db;
    Bugzilla->switch_to_main_db if $is_shadow_db;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction;

    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    my $log_message = sprintf(
        "REVISION CHANGE FOUND: D%d: %s | bug: %d | %s",
        $revision->id,
        $revision->title,
        $revision->bug_id,
        $story_text);
    $self->logger->info($log_message);

    my $bug = Bugzilla::Bug->new($revision->bug_id);

    # REVISION SECURITY POLICY

    # If bug is public then remove privacy policy
    my $result;
    if (!@{ $bug->groups_in }) {
        $revision->set_policy('view', 'public');
        $revision->set_policy('edit', 'users');
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

        $revision->set_policy('view', $policy_phid);
        $revision->set_policy('edit', $policy_phid);
        $revision->set_subscribers($subscribers);
    }

    my $attachment = create_revision_attachment($bug, $revision->id, $revision->title, $timestamp);

    # ATTACHMENT OBSOLETES

    # fixup attachments on current bug
    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    foreach my $attachment (@attachments) {
        my ($attach_revision_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
        next if $attach_revision_id != $revision->id;

        my $make_obsolete = $revision->status eq 'abandoned' ? 1 : 0;
        $attachment->set_is_obsolete($make_obsolete);

        if ($revision->id == $attach_revision_id
            && $revision->title ne $attachment->description) {
            $attachment->set_description($revision->title);
        }

        $attachment->update($timestamp);
        last;
    }

    # fixup attachments with same revision id but on different bugs
    my $other_attachments = Bugzilla::Attachment->match({
        mimetype => PHAB_CONTENT_TYPE,
        filename => 'phabricator-D' . $revision->id . '-url.txt',
        WHERE    => { 'bug_id != ? AND NOT isobsolete' => $bug->id }
    });
    foreach my $attachment (@$other_attachments) {
        $attachment->set_is_obsolete(1);
        $attachment->update($timestamp);
    }

    # FINISH UP

    $bug->update($timestamp);
    $revision->update();

    Bugzilla::BugMail::Send($revision->bug_id, { changer => Bugzilla->user });

    $dbh->bz_commit_transaction;
    Bugzilla->switch_to_shadow_db if $is_shadow_db;

    Bugzilla->set_user($old_user);

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
