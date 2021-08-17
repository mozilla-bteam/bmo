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
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Attachment;
use Bugzilla::Extension::Webhooks::Webhook;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util (mojo_user_agent);

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
  my $product = $webhook->product_name;
  my $component = $webhook->component_name ? $webhook->component_name : 'any';

  my $payload  = $message->payload_decoded;
  my $target   = $payload->{event}->{target};
  my $bug_data = $target eq 'bug' ? $payload->{bug} : $payload->{$target}->{bug};
  $bug_data || return 0;

  my $bug = Bugzilla::Bug->new({id => $bug_data->{id}, cache => 1});

  if ($product eq $bug->product
    && ($component eq $bug->component || $component eq 'any'))
  {
    if ( ($event =~ /create/ && $message->routing_key eq 'bug.create')
      || ($event =~ /change/ && $message->routing_key =~ /^bug\.modify/)
      || ($event =~ /comment/    && $message->routing_key eq 'comment.create')
      || ($event =~ /attachment/ && $message->routing_key eq 'attachment.create'))
    {
      return 1;
    }
  }

  return 0;
}

sub send {
  my ($self, $message) = @_;

  try {
    my $webhook = Bugzilla::Extension::Webhooks::Webhook->new($self->{webhook_id});

    my $payload = $message->payload_decoded;
    $payload->{webhook_name} = $webhook->name;
    $payload->{webhook_id}   = $webhook->id;

    my $target            = $payload->{event}->{target};
    my $target_is_private = $payload->{$target}->{is_private};

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


    my $tx = mojo_user_agent()->post($webhook->url,
      {'Content-Type' => 'application/json', 'Accept' => 'application/json'} =>
        json => $payload);
    if ($tx->res->code != 200) {
      die 'Expected HTTP 200, got '
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

1;
