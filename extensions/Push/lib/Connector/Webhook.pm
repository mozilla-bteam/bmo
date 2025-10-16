# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Webhook;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Hook;
use Bugzilla::Extension::Webhooks::Webhook;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util qw(mojo_user_agent);

use JSON qw(decode_json encode_json);
use List::MoreUtils qw(any);
use Try::Tiny;

sub new {
  my ($class, $webhook_id) = @_;
  my $self = {};
  bless($self, $class);
  $self->{name}       = 'Webhook_' . $webhook_id;
  $self->{webhook_id} = $webhook_id;
  $self->init();
  return $self;
}

sub load_config {
  my ($self) = @_;
  my $config
    = Bugzilla::Extension::Push::Config->new($self->name, $self->options);
  $config->option('enabled')->{'default'} = 'Enabled';
  $config->load();
  $self->{config} = $config;
}

sub save {
  my ($self) = @_;
  my $dbh    = Bugzilla->dbh;
  my $push   = Bugzilla->push_ext;
  $dbh->bz_start_transaction();
  $self->config->update();
  $push->set_config_last_modified();
  $dbh->bz_commit_transaction();
}

sub should_send {
  my ($self, $message) = @_;

  return 0 unless Bugzilla->params->{webhooks_enabled};

  my $webhook = Bugzilla::Extension::Webhooks::Webhook->new($self->{webhook_id});
  my $event   = $webhook->event;
  my $product   = $webhook->product_name;
  my $component = $webhook->component_name;

  my $payload  = $message->payload_decoded;
  my $target   = $payload->{event}->{target};
  my $bug_data = $target eq 'bug' ? $payload->{bug} : $payload->{$target}->{bug};
  $bug_data || return 0;

  return 0 if !_owner_can_see($webhook, $message, $payload);

  if (($product eq $bug_data->{product} || $product eq 'Any')
    && ($component eq $bug_data->{component} || $component eq 'Any'))
  {
    if ( ($event =~ /create/ && $message->routing_key eq 'bug.create')
      || ($event =~ /change/ && $message->routing_key =~ /^bug\.modify/)
      || ($event =~ /comment/    && $message->routing_key eq 'comment.create')
      || ($event =~ /attachment_change/ && $message->routing_key =~ /^attachment[.]modify/)
      || ($event =~ /attachment/ && $message->routing_key eq 'attachment.create'))
    {
      return 1;
    }
  }

  # check if the bug was removed from a product/component we care about
  if ($event =~ /change/ && $message->routing_key =~ /\Qbug.modify\E/) {
    my $removed_product = "";
    my $removed_component = "";
    if (exists $bug_data->{'changes'}) {
      foreach my $change ($bug_data->{'changes'}) {
        if ($change->{'field'} eq 'product') {
          $removed_product = $change->{'removed'};
        }
        if ($change->{'field'} eq 'component') {
          $removed_component = $change->{'removed'};
        }
      }
    }
    if ($removed_product || $removed_component) {
      if ($removed_product eq '') {
        $removed_product = $bug_data->{'product'};
      }
      if ($product eq $removed_product
          && ($component eq $removed_component || $component eq 'any'))
      {
        return 1;
      }
    }
  }

  return 0;
}

sub send {
  my ($self, $message) = @_;

  try {
    my $webhook = Bugzilla::Extension::Webhooks::Webhook->new($self->{webhook_id});

    my $payload = $message->payload_decoded;

    # Check visibilty again in case bug security changed since this message was queued
    return PUSH_RESULT_BLOCKED if !_owner_can_see($webhook, $message, $payload);

    # Add webhook information to the payload
    $payload->{webhook_name} = $webhook->name;
    $payload->{webhook_id}   = $webhook->id;

    my $target = $payload->{event}->{target};

    # If comment or attachment is NOT private but bug IS private
    # then entire target is private
    my $target_is_private = ($payload->{$target}->{is_private}
        || $payload->{$target}->{bug}->{is_private}) ? 1 : 0;

    my $bug_data;
    if ($target_is_private && ($target eq 'attachment' || $target eq 'comment')) {
      $bug_data = {
        id         => $payload->{$target}->{bug}->{id},
        is_private => $payload->{$target}->{bug}->{is_private},
        $target    => {
          id         => _integer($payload->{$target}->{id}),
          is_private => _boolean($target_is_private),
        }
      };
    }
    elsif ($target_is_private && $target eq 'bug') {
      $bug_data = {
        id         => _integer($payload->{$target}->{id}),
        is_private => _boolean($target_is_private),
      };
    }
    elsif ($target eq 'bug') {
      $bug_data = $payload->{$target};
    }
    else {
      $bug_data = $payload->{$target}->{bug};
      $bug_data->{$target} = $payload->{$target};
      delete $bug_data->{$target}->{bug};
    }

    if ($target_is_private && $payload->{event}->{action} eq 'modify') {
      delete $payload->{event}->{changes};
    }

    delete $payload->{$target};
    $payload->{bug} = $bug_data;

    delete $payload->{event}->{change_set};

    my $headers
      = {'Content-Type' => 'application/json', 'Accept' => 'application/json'};
    if ($webhook->api_key_header && $webhook->api_key_value) {
      $headers->{$webhook->api_key_header} = $webhook->api_key_value;
    }

    Bugzilla::Hook::process('webhook_before_send',
      {webhook => $webhook, payload => $payload});

    my $tx = mojo_user_agent()->post($webhook->url, $headers => json => $payload);
    if (!$tx->res->is_success) {
      die 'Expected HTTP 2xx, got '
        . $tx->res->code . ' ('
        . $tx->error->{message} . ') '
        . $tx->res->body;
    }
    else {
      return PUSH_RESULT_OK;
    }
  }
  catch {
    return (PUSH_RESULT_TRANSIENT, clean_error($_));
  };
}

# Private methods

sub _boolean {
  my ($value) = @_;
  return $value ? JSON::true : JSON::false;
}

sub _integer {
  my ($value) = @_;
  return defined($value) ? $value + 0 : undef;
}

sub _owner_can_see {
  my ($webhook, $message, $payload) = @_;
  my $target   = $payload->{event}->{target};
  my $bug_data = $target eq 'bug' ? $payload->{bug} : $payload->{$target}->{bug};

  # Do not send if webhook owner cannot see the bug or the product the bug is filed under.
  # Although we do want to send if the bug went from public to private in the latest change.
  my $owner = $webhook->user;
  if (
    (
         !$owner->can_see_bug($bug_data->{id})
      || !$owner->can_see_product($bug_data->{product})
    )
    && $message->routing_key ne 'bug.modify:is_private'
    )
  {
    return 0;
  }

  # If target is a comment or attachment, do not send if the webhook owner is
  # not in the insiders group used for private comments/attachments.
  if ( ($target eq 'comment' || $target eq 'attachment')
    && $payload->{$target}->{is_private}
    && !$owner->is_insider)
  {
    return 0;
  }

  return 1;
}

1;
