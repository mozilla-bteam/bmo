# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::JiraWebhookSync;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Bug;
use Bugzilla::BugUrl;
use Bugzilla::Extension::JiraWebhookSync::JiraBugMap;
use Bugzilla::Logging;
use Bugzilla::Util qw(trim);

use JSON::MaybeXS qw(decode_json);
use List::Util    qw(none uniq);
use Mojo::URL;
use Mojo::Util qw(dumper);

# Creates/updates database schema for the extension
sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{schema}->{jira_bug_map} = {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE',}
      },
      jira_url => {TYPE => 'VARCHAR(255)', NOTNULL => 1,},
      jira_project_key => {TYPE => 'VARCHAR(100)', NOTNULL => 1,},
    ],
    INDEXES => [
      jira_bug_map_bug_id_idx => {FIELDS => ['bug_id', 'jira_url'], TYPE => 'UNIQUE',},
      jira_bug_map_project_idx => ['jira_project_key'],
    ],
  };
}

sub install_update_db {
  my ($self) = @_;
  my $dbh = Bugzilla->dbh;

  if (!$dbh->bz_column_info('jira_bug_map', 'jira_url')) {
    $dbh->bz_add_column('jira_bug_map', 'jira_url', {TYPE => 'VARCHAR(255)'});

    my $jira_rows
      = $dbh->selectall_arrayref('SELECT id, jira_id FROM jira_bug_map');
    foreach my $row (@{$jira_rows}) {
      my ($id, $jira_id) = @{$row};
      my $jira_url = "https://mozilla-hub.atlassian.net/browse/$jira_id";
      $dbh->do('UPDATE jira_bug_map SET jira_url = ? WHERE id = ?', undef, $jira_url,
        $id);
    }

    $dbh->bz_drop_column('jira_bug_map', 'jira_id');
    $dbh->bz_alter_column('jira_bug_map', 'jira_url',
      {TYPE => 'VARCHAR(255)', NOTNULL => 1});
  }
}

# Adds the JiraWebhookSync configuration panel to the admin interface.
# This hook allows administrators to configure Jira webhook synchronization settings.
sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{JiraWebhookSync} = 'Bugzilla::Extension::JiraWebhookSync::Config';
}

# Intercepts see_also additions to check if they should be stored in the mapping table
# instead of as regular see_also links. This is used to work around JBI design choices
# that require the see_also value to not exist to prevent duplicate jira tickets.
sub bug_start_of_update {
  my ($self, $args) = @_;
  my $new_bug = $args->{bug};

  foreach my $see_also (@{$new_bug->see_also}) {
    my $see_also_url = $see_also->name;

    # Check if this see_also URL corresponds to a Jira ticket
    my $project_key
      = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->extract_jira_project_key(
      $see_also_url);

    next unless $project_key;

    INFO(
      "Intercepting see_also for Jira ticket: $see_also_url (project: $project_key)");

# Add the jira id and project key to the jira_bug_map table unless it already exists
    my $existing_map
      = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->get_by_bug_id(
      $new_bug->id);
    if (!$existing_map) {
      INFO('Creating new Jira mapping for bug ' . $new_bug->id);
      Bugzilla::Extension::JiraWebhookSync::JiraBugMap->create({
        bug_id           => $new_bug->id,
        jira_url         => $see_also_url,
        jira_project_key => $project_key,
      });
    }

    # Remove the see_also entry from the new bug object
    $new_bug->remove_see_also($see_also);
  }
}

# Modifies webhook payload before sending by adding configured whiteboard tags
# and see_also values from the mapping table.
# Checks if the bug's product/component matches any configuration rules and
# automatically adds the corresponding whiteboard tag to the payload if matched.
# Also checks if there's a Jira mapping for this bug and adds the Jira URL to see_also.
sub webhook_before_send {
  my ($self, $args) = @_;
  my $webhook = $args->{webhook};
  my $payload = $args->{payload};
  my $params  = Bugzilla->params;

  my $hostname = $params->{jira_webhook_sync_hostname};
  return if !$hostname;

  # Only process webhooks destined for the configured Jira hostname
  my $uri = Mojo::URL->new($webhook->url);
  return if $uri->host ne $hostname;

  # Get the bug object from the payload
  my $bug_id = $payload->{bug}->{id};

  INFO("Processing webhook for bug $bug_id to Jira host $hostname");

  # Check if there's a Jira mapping for this bug
  if (my $jira_map
    = Bugzilla::Extension::JiraWebhookSync::JiraBugMap->get_by_bug_id($bug_id))
  {
    INFO('Adding Jira see_also to webhook payload: ' . $jira_map->jira_url);

    # Add the Jira URL to the see_also array in the payload if not already present
    $payload->{bug}->{see_also} ||= [];
    if (none { $_ eq $jira_map->jira_url } @{$payload->{bug}->{see_also}}) {
      push @{$payload->{bug}->{see_also}}, $jira_map->jira_url;
    }
  }

  # Make copy of the current whiteboard value
  my $whiteboard = $payload->{bug}->{whiteboard};

  my $config = decode_json($params->{jira_webhook_sync_config});

  my @new_tags;
  foreach my $whiteboard_tag (keys %{$config}) {
    INFO('Processing whiteboard tag in config: ' . $whiteboard_tag);

    if (_bug_matches_rule($payload->{bug}, $config->{$whiteboard_tag})) {
      INFO('Bug matches rule for tag: ' . $whiteboard_tag);
      push @new_tags, $whiteboard_tag;
    }
  }

  $payload->{bug}->{whiteboard} = _add_whiteboard_tags($whiteboard, \@new_tags);
}

# Adds a whiteboard tag to the whiteboard string if it doesn't already exist.
# Returns the whiteboard value with the tag in [brackets] format.
# If the tag already exists, returns the whiteboard unchanged.
sub _add_whiteboard_tags {
  my ($whiteboard, $new_tags) = @_;

  $new_tags = [uniq @{$new_tags}];    # Remove duplicates

  foreach my $new_tag (@{$new_tags}) {
    INFO("whiteboard merge: $whiteboard, $new_tag");
    next if $whiteboard =~ /\[\Q$new_tag\E\]/;    # Whiteboard already has tag
    $whiteboard .= " [$new_tag]";                 # Append new tag to the end
  }

  return trim($whiteboard);                       # Trim whitespace before returning
}

# Checks if a bug matches the criteria defined in a rule.
sub _bug_matches_rule {
  my ($bug, $rule) = @_;

  return 0 unless exists $rule->{product};
  return 0 unless $rule->{product} eq $bug->{product};

  INFO('Product matched: ' . $rule->{product});

  return 1 if !exists $rule->{component};

  if ($rule->{component} eq $bug->{component}) {
    INFO('Component matched: ' . $rule->{component});
    return 1;
  }

  return 0;
}

__PACKAGE__->NAME;
