# This Source Code Form is subject to the terms of the Mozilla Public
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::JiraWebhookSync;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Logging;
use JSON::MaybeXS qw(decode_json);
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

  foreach my $whiteboard_tag (keys %{$config}) {
    INFO('Processing whiteboard tag in config: ' . $whiteboard_tag);

    my $criteria = $config->{$whiteboard_tag};
    my $matched  = 0;

    if (exists $criteria->{product}
      && $criteria->{product} eq $payload->{bug}->{product})
    {
      INFO('Product matched: ' . $criteria->{product});
      if (!exists $criteria->{component}) {
        $matched = 1;    # Matches any component
      }
      else {
        if ($criteria->{component} eq $payload->{bug}->{component}) {
          INFO('Component matched: ' . $criteria->{component});
          $matched = 1;
        }
      }
    }

    if ($matched) {
      $whiteboard = _add_whiteboard_tag($whiteboard, $whiteboard_tag);
    }
  }

  $payload->{bug}->{whiteboard} = $whiteboard;
}

# Adds a whiteboard tag to the whiteboard string if it doesn't already exist.
# Returns the whiteboard value with the tag in [brackets] format.
# If the tag already exists, returns the whiteboard unchanged.
sub _add_whiteboard_tag {
  my ($whiteboard, $new_tag) = @_;
  INFO("whiteboard merge: $whiteboard, $new_tag");
  return "[$new_tag]" if !$whiteboard;                         # Blank whiteboard value
  return $whiteboard  if $whiteboard =~ /\[\Q$new_tag\E\]/;    # Whiteboard already has tag
  return $whiteboard . " [$new_tag]";                          # Append new tag to the end
}

__PACKAGE__->NAME;
