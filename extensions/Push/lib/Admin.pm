# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Admin;

use 5.10.1;
use strict;
use warnings;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Extension::Webhooks::Webhook;
use Bugzilla::Token qw(check_hash_token);
use Bugzilla::Util qw(trim detaint_natural );

use base qw(Exporter);
our @EXPORT = qw(
  admin_config
  admin_queues
  admin_log
  admin_webhooks
);

sub admin_config {
  my ($vars) = @_;
  my $push   = Bugzilla->push_ext;
  my $input  = Bugzilla->input_params;

  if ($input->{save}) {
    my $token = $input->{token};
    check_hash_token($token, ['push_config']);
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();
    _update_config_from_form('global', $push->config);
    foreach my $connector ($push->connectors->list) {
      if ($connector->name !~ /\QWebhook\E/) {
        _update_config_from_form($connector->name, $connector->config);
      }
    }
    $push->set_config_last_modified();
    $dbh->bz_commit_transaction();
    $vars->{message} = 'push_config_updated';
  }

  $vars->{push}       = $push;
  $vars->{connectors} = $push->connectors;
}

sub _update_config_from_form {
  my ($name, $config) = @_;
  my $input = Bugzilla->input_params;

  # read values from form
  my $values = {};
  foreach my $option ($config->options) {
    my $option_name = $option->{name};
    $values->{$option_name} = trim($input->{$name . ".$option_name"});
  }

  # validate
  if ($values->{enabled} eq 'Enabled') {
    eval { $config->validate($values); };
    if ($@) {
      ThrowUserError('push_error', {error_message => clean_error($@)});
    }
  }

  # update
  foreach my $option ($config->options) {
    my $option_name = $option->{name};
    $config->{$option_name} = $values->{$option_name};
  }
  $config->update();
}

sub admin_queues {
  my ($vars, $page) = @_;
  my $push  = Bugzilla->push_ext;
  my $input = Bugzilla->input_params;

  if ($page eq 'push_queues.html') {
    $vars->{push} = $push;

  }
  elsif ($page eq 'push_queues_view.html') {
    my $queue;
    if ($input->{connector}) {
      my $connector = $push->connectors->by_name($input->{connector})
        || ThrowUserError('push_error', {error_message => 'Invalid connector'});
      $queue = $connector->backlog;
    }
    else {
      $queue = $push->queue;
    }
    $vars->{queue} = $queue;

    my $id = $input->{message} || 0;
    detaint_natural($id)
      || ThrowUserError('push_error', {error_message => 'Invalid message ID'});
    my $message = $queue->by_id($id)
      || ThrowUserError('push_error', {error_message => 'Invalid message ID'});

    if ($input->{delete}) {
      my $token = $input->{token};
      check_hash_token($token, ['deleteMessage']);
      $message->remove_from_db();
      $vars->{message} = 'push_message_deleted';

    }
    else {
      $vars->{message_obj} = $message;
      eval { $vars->{json} = to_json($message->payload_decoded, 1); };
    }
  }
}

sub admin_log {
  my ($vars) = @_;
  my $push   = Bugzilla->push_ext;
  my $input  = Bugzilla->input_params;

  $vars->{push} = $push;
}

sub admin_webhooks {
  my ($vars)   = @_;
  my $push     = Bugzilla->push_ext;
  my $input    = Bugzilla->input_params;
  my @webhooks = Bugzilla::Extension::Webhooks::Webhook->get_all;

  if ($input->{save}) {
    my $token = $input->{token};
    check_hash_token($token, ['webhooks_config']);
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();
    foreach my $connector ($push->connectors->list) {
      if ($connector->name =~ /\QWebhook\E/) {
        _update_webhook_status($connector);
      }
    }
    $push->set_config_last_modified();
    $dbh->bz_commit_transaction();
    $vars->{message} = 'push_config_updated';
  }

  $vars->{push}       = $push;
  $vars->{connectors} = $push->connectors;
  $vars->{webhooks}   = \@webhooks;
}

sub _update_webhook_status {
  my ($connector) = @_;
  my $input        = Bugzilla->input_params;
  my $config       = $connector->config;
  my $was_disabled = $connector->enabled ? 0 : 1;
  my $status       = trim($input->{$connector->name . ".enabled"});

  # Save the new status of the webhook to the database
  $config->{enabled} = $status;
  $config->update();

  # This might have been disabled due to large number of errors.
  # In that case we want to reset the attempts to 0 if we are
  # re-enabling the webhook
  if ($was_disabled && $status eq 'Enabled') {
    $connector->backlog->reset_backoff;
    my $message = $connector->backlog->oldest;
    $message->{attempts} = 0;
    $message->update;
  }
}

1;
