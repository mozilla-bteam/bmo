# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Phabricator;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(
  add_comment_to_revision
  add_security_sync_comments
  create_private_revision_policy
  edit_revision_policy
  get_attachment_revisions
  get_bug_role_phids
  get_project_phid
  get_security_sync_groups
  intersect
  make_revision_public
  make_revision_private
  set_revision_subscribers
);
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util qw(is_public);

sub options {
    return (
        {
            name     => 'phabricator_url',
            label    => 'Phabricator URL',
            type     => 'string',
            default  => '',
            required => 1,
        }
    );
}

sub should_send {
    my ( $self, $message ) = @_;

    return 0 unless Bugzilla->params->{phabricator_enabled};

    # We are only interested currently in bug group, assignee, qa-contact, or cc changes.
    return 0
      unless $message->routing_key =~
      /^(?:attachment|bug)\.modify:.*\b(bug_group|assigned_to|qa_contact|cc)\b/;

    my $bug = $self->_get_bug_by_data( $message->payload_decoded ) || return 0;

    return $bug->has_attachment_with_mimetype(PHAB_CONTENT_TYPE);
}

sub send {
    my ( $self, $message ) = @_;

    my $logger = Bugzilla->push_ext->logger;

    my $data = $message->payload_decoded;

    my $bug = $self->_get_bug_by_data($data) || return PUSH_RESULT_OK;

    my $is_public = is_public($bug);

    my @set_groups = get_security_sync_groups($bug);

    my @revisions = get_attachment_revisions($bug);

    if (!$is_public && !@set_groups) {
        foreach my $revision (@revisions) {
            Bugzilla->audit(sprintf(
              'Making revision %s for bug %s private due to unkown Bugzilla groups: %s',
              $revision->{id},
              $bug->id,
              join(', ', @set_groups)
            ));
            make_revision_private( $revision->{phid} );
        }

        add_security_sync_comments(\@revisions, $bug);

        return PUSH_RESULT_OK;
    }

    my $group_change =
      ($message->routing_key =~ /^(?:attachment|bug)\.modify:.*\bbug_group\b/)
      ? 1
      : 0;

    my $subscribers;
    if ( !$is_public ) {
        $subscribers = get_bug_role_phids($bug);
    }

    my $secure_project_phid = get_project_phid('secure-revision');

    foreach my $revision (@revisions) {
        my $revision_phid = $revision->{phid};

        my $rev_obj = Bugzilla::Extension::PhabBugz::Revision->new_from_query({ phids => [ $revision_phid ] });
        my $revision_updated;

        if ( $is_public && $group_change ) {
            Bugzilla->audit(sprintf(
              'Making revision %s public for bug %s',
              $revision->{id},
              $bug->id
            ));
            make_revision_public($revision_phid);
            $rev_obj->remove_project($secure_project_phid);
            $revision_updated = 1;
        }
        elsif ( !$is_public && $group_change ) {
            Bugzilla->audit(sprintf(
              'Giving revision %s a custom policy for bug %s',
              $revision->{id},
              $bug->id
            ));
            my $policy_phid = create_private_revision_policy( $bug, \@set_groups );
            edit_revision_policy( $revision_phid, $policy_phid, $subscribers );
            $rev_obj->add_project($secure_project_phid);
            $revision_updated = 1;
        }
        elsif ( !$is_public && !$group_change ) {
            Bugzilla->audit(sprintf(
              'Updating subscribers for %s for bug %s',
              $revision->{id},
              $bug->id
            ));
            set_revision_subscribers( $revision_phid, $subscribers );
        }
        $rev_obj->update() if $revision_updated;
    }

    return PUSH_RESULT_OK;
}

sub _get_bug_by_data {
    my ( $self, $data ) = @_;
    my $bug_data = $self->_get_bug_data($data) || return 0;
    my $bug = Bugzilla::Bug->new( { id => $bug_data->{id} } );
}

sub _get_bug_data {
    my ( $self, $data ) = @_;
    my $target = $data->{event}->{target};
    if ( $target eq 'bug' ) {
        return $data->{bug};
    }
    elsif ( exists $data->{$target}->{bug} ) {
        return $data->{$target}->{bug};
    }
    else {
        return;
    }
}

1;
