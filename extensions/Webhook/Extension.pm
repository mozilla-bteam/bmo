# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Webhook;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Component;
use Bugzilla::Product;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::Webhook::webhook;
use Bugzilla::User;

#
# installation
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  my $dbh = Bugzilla->dbh;
  $args->{'schema'}->{'webhook'} = {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE',}
      },
      name  => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      url   => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      event => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE',}
      },
      product_id   => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE',}
      }
    ],
  };
}

sub db_sanitize {
  my $dbh = Bugzilla->dbh;
  print "Deleting webhooks...\n";
  $dbh->do("DELETE FROM webhook");
}

#
# preferences
#

sub user_preferences {
  my ($self, $args) = @_;
  return unless $args->{'current_tab'} eq 'webhook';

  my $input = Bugzilla->input_params;
  my $user  = Bugzilla->user;
  my $vars  = $args->{vars};

  if ($args->{'save_changes'}) {

    if ($input->{'add_webhook'}) {

      # add webhook

      my $params = {user_id => Bugzilla->user->id,};
      $params->{name} = $input->{name};
      $params->{url} = $input->{url};

      if ($input->{create_event} == 1 && $input->{change_event} == 1) {
        $params->{event} = 'create,change';
      }
      elsif ($input->{create_event} == 1) {
        $params->{event} = 'create';
      }
      elsif ($input->{change_event} == 1) {
        $params->{event} = 'change';
      }
      #else {
        #THROW ERROR MUST SELECT AT LEAST ONE
      #}

      if (my $product_name = $input->{product}) {
        my $product = Bugzilla::Product->check({name => $product_name, cache => 1});
        $params->{product_id} = $product->id;

        if (my $component_name = $input->{component}) {
          $params->{component_id}
            = Bugzilla::Component->check({
            name => $component_name, product => $product, cache => 1
            })->id;
        }
        else {
          $params->{component_id} = IS_NULL;
        }
      }
      else {
        $params->{product_id}   = IS_NULL;
        $params->{component_id} = IS_NULL;
      }

      Bugzilla::Extension::Webhook::webhook->create($params);

    }
    else {

      # remove webhook(s)

      my $ids  = ref($input->{remove}) ? $input->{remove} : [$input->{remove}];
      my $dbh  = Bugzilla->dbh;
      my $user = Bugzilla->user;

      my $webhooks = Bugzilla::Extension::Webhook::webhook->match(
        {id => $ids, user_id => $user->id});
      $dbh->bz_start_transaction;
      foreach my $webhook (@$webhooks) {
        $webhook->remove_from_db();
      }
      $dbh->bz_commit_transaction;

    }
  }

  $vars->{webhooks} = [
    sort {
           $a->product_name cmp $b->product_name
        || $a->component_name cmp $b->component_name
    } @{Bugzilla::Extension::Webhook::webhook->match({
        user_id => Bugzilla->user->id,
      })
    }
  ];

  ${$args->{handled}} = 1;
}

__PACKAGE__->NAME;
