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

use Bugzilla::Logging;
use Bugzilla::Util qw(trim);

use JSON::MaybeXS qw(decode_json);
use List::Util    qw(uniq);
use Mojo::URL;
use Mojo::Util qw(dumper);

# Adds the JiraWebhookSync configuration panel to the admin interface.
# This hook allows administrators to configure Jira webhook synchronization settings.
sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{JiraWebhookSync} = 'Bugzilla::Extension::JiraWebhookSync::Config';
}

# Modifies webhook payload before sending by adding configured whiteboard tags.
# Checks if the bug's product/component matches any configuration rules and
# automatically adds the corresponding whiteboard tag to the payload if matched.
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

  $payload->{bug}->{whiteboard}
    = _add_whiteboard_tags($whiteboard, \@new_tags);
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

  return trim($whiteboard); # Trim whitespace before returning
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
