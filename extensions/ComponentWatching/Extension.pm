# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ComponentWatching;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(detaint_natural trim trick_taint);

our $VERSION = '2';

use constant REQUIRE_WATCH_USER => 1;
use constant DEFAULT_ASSIGNEE   => 'nobody@mozilla.org';

use constant REL_COMPONENT_WATCHER => 15;

#
# installation
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  my $dbh = Bugzilla->dbh;

  # Bugzilla 5.0+, the components.id type
  # is INT3, while earlier versions used INT2
  my $component_id_type = 'INT2';
  my $len               = scalar @{$args->{schema}->{components}->{FIELDS}};
  for (my $i = 0; $i < $len - 1; $i += 2) {
    next if $args->{schema}->{components}->{FIELDS}->[$i] ne 'id';
    $component_id_type = 'INT3'
      if $args->{schema}->{components}->{FIELDS}->[$i + 1]->{TYPE} eq
      'MEDIUMSERIAL';
    last;
  }
  $args->{'schema'}->{'component_watch'} = {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE',}
      },
      component_id => {
        TYPE       => $component_id_type,
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE',}
      },
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE',}
      },
      component_prefix => {TYPE => 'VARCHAR(64)', NOTNULL => 0,},
    ],
  };
}

sub install_update_db {
  my $dbh = Bugzilla->dbh;
  $dbh->bz_add_column(
    'components',
    'watch_user',
    {
      TYPE       => 'INT3',
      REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'SET NULL',}
    }
  );
  $dbh->bz_add_column('component_watch', 'id',
    {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
  );
  $dbh->bz_add_column('component_watch', 'component_prefix',
    {TYPE => 'VARCHAR(64)', NOTNULL => 0,});
}

#
# templates
#

sub template_before_create {
  my ($self, $args) = @_;
  my $config    = $args->{config};
  my $constants = $config->{VARIABLES}{constants};
  $constants->{REL_COMPONENT_WATCHER} = REL_COMPONENT_WATCHER;
}

sub template_before_process {
  my ($self, $args) = @_;
  return unless $args->{file} eq 'admin/components/create.html.tmpl';
  $args->{vars}{comp}{default_assignee}{login} = DEFAULT_ASSIGNEE;
}

#
# user-watch
#

BEGIN {
  *Bugzilla::Component::watch_user = \&_component_watch_user;
}

sub _component_watch_user {
  my ($self) = @_;
  return unless $self->{watch_user};
  $self->{watch_user_object} ||= Bugzilla::User->new($self->{watch_user});
  return $self->{watch_user_object};
}

sub object_columns {
  my ($self, $args) = @_;
  my $class   = $args->{class};
  my $columns = $args->{columns};
  return unless $class->isa('Bugzilla::Component');

  push(@$columns, 'watch_user');
}

sub object_update_columns {
  my ($self, $args) = @_;
  my $object  = $args->{object};
  my $columns = $args->{columns};
  return unless $object->isa('Bugzilla::Component');

  push(@$columns, 'watch_user');

  # add the user if not yet exists and user chooses 'automatic'
  $self->_create_watch_user();

  # editcomponents.cgi doesn't call set_all, so we have to do this here
  my $input = Bugzilla->input_params;
  $object->set('watch_user', $input->{watch_user});
}

sub object_validators {
  my ($self, $args) = @_;
  my $class      = $args->{class};
  my $validators = $args->{validators};
  return unless $class->isa('Bugzilla::Component');

  $validators->{watch_user} = \&_check_watch_user;
}

sub object_before_create {
  my ($self, $args) = @_;
  my $class  = $args->{class};
  my $params = $args->{params};
  return unless $class->isa('Bugzilla::Component');

  # We need to create a watch user for the default product/component
  # if we are creating the database for the first time.
  my $dbh = Bugzilla->dbh;
  if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE
    && !$dbh->selectrow_array('SELECT 1 FROM components'))
  {
    my $watch_user = Bugzilla::User->create({
      login_name    => 'testcomponent@testproduct.bugs',
      cryptpassword => '*',
      disable_mail  => 1
    });
    $params->{watch_user} = $watch_user->login;
  }
  else {
    my $input = Bugzilla->input_params;
    $params->{watch_user} = $input->{watch_user};
    $self->_create_watch_user();
  }
}

sub object_end_of_update {
  my ($self, $args) = @_;
  my $object     = $args->{object};
  my $old_object = $args->{old_object};
  my $changes    = $args->{changes};
  return unless $object->isa('Bugzilla::Component');

  my $old_id = $old_object->watch_user ? $old_object->watch_user->id : 0;
  my $new_id = $object->watch_user     ? $object->watch_user->id     : 0;
  if ($old_id != $new_id) {
    $changes->{watch_user} = [$old_id ? $old_id : undef, $new_id ? $new_id : undef];
  }

# when a component is renamed, update the watch-user to follow
# this only happens when the user appears to have been auto-generated from the old name
  if ( $changes->{name}
    && $old_object->watch_user
    && $object->watch_user
    && $old_object->watch_user->id == $object->watch_user->id
    && _generate_watch_user_name($old_object) eq $object->watch_user->login)
  {
    my $old_login = $object->watch_user->login;
    $object->watch_user->set_login(_generate_watch_user_name($object));
    $object->watch_user->update();
    $changes->{watch_user_login} = [$old_login, $object->watch_user->login];
  }
}

sub _generate_watch_user_name {

# this is mirrored in template/en/default/hook/admin/components/edit-common-rows.html.tmpl
# that javascript needs to be kept in sync with this perl
  my ($component) = @_;
  return
      _sanitise_name($component->name) . '@'
    . _sanitise_name($component->product->name) . '.bugs';
}

sub _sanitise_name {
  my ($name) = @_;
  $name = lc($name);
  $name =~ s/[^a-z0-9_]/-/g;
  $name =~ s/-+/-/g;
  $name =~ s/(^-|-$)//g;
  return $name;
}

sub _create_watch_user {
  my $input = Bugzilla->input_params;
  if ($input->{watch_user_auto}
    && !Bugzilla::User->new({name => $input->{watch_user}}))
  {
    Bugzilla::User->create({
      login_name => $input->{watch_user}, cryptpassword => '*',
    });
  }
}

sub _check_watch_user {
  my ($self, $value, $field) = @_;
  $value = trim($value || '');
  return undef if !REQUIRE_WATCH_USER && $value eq '';
  if ($value eq '') {
    ThrowUserError('component_watch_missing_watch_user');
  }
  if ($value !~ /\.bugs$/i) {
    ThrowUserError('component_watch_invalid_watch_user');
  }
  return Bugzilla::User->check($value)->id;
}

#
# preferences
#

sub user_preferences {
  my ($self, $args) = @_;
  my $tab = $args->{'current_tab'};
  return unless $tab eq 'component_watch';

  my $save    = $args->{'save_changes'};
  my $handled = $args->{'handled'};
  my $vars    = $args->{'vars'};
  my $user    = Bugzilla->user;
  my $input   = Bugzilla->input_params;

  if ($save) {
    if ($input->{'add'} && $input->{'add_product'}) {

      # add watch

      # load product and verify access
      my $productName = $input->{'add_product'};
      my $product = Bugzilla::Product->new({name => $productName, cache => 1});
      unless ($product && $user->can_access_product($product)) {
        ThrowUserError('product_access_denied', {product => $productName});
      }

      # starting-with
      if (my $prefix = $input->{add_starting}) {
        _addPrefixWatch($user, $product, $prefix);

      }
      else {
        my $ra_componentNames = $input->{'add_component'};
        $ra_componentNames = [$ra_componentNames || ''] unless ref($ra_componentNames);

        if (grep { $_ eq '' } @$ra_componentNames) {

          # watching a product
          _addProductWatch($user, $product);

        }
        else {
          # watching specific components
          foreach my $componentName (@$ra_componentNames) {
            my $component
              = Bugzilla::Component->new({
              name => $componentName, product => $product, cache => 1
              });
            unless ($component) {
              ThrowUserError('product_access_denied', {product => $productName});
            }
            _addComponentWatch($user, $component);
          }
        }
      }

      _addDefaultSettings($user);

    }
    else {
      # remove watch(s)

      my $delete
        = ref $input->{del_watch} ? $input->{del_watch} : [$input->{del_watch}];
      foreach my $id (@$delete) {
        _deleteWatch($user, $id);
      }
    }

  }

  $vars->{'add_product'}   = $input->{'product'};
  $vars->{'add_component'} = $input->{'component'};
  $vars->{'watches'}       = _getWatches($user);
  $vars->{'user_watches'}  = _getUserWatches($user);

  $$handled = 1;
}

#
# bugmail
#

sub bugmail_recipients {
  my ($self, $args) = @_;
  my $bug        = $args->{'bug'};
  my $recipients = $args->{'recipients'};
  my $diffs      = $args->{'diffs'};

  my ($oldProductId, $newProductId) = ($bug->product_id, $bug->product_id);
  my ($oldComponentId, $newComponentId)
    = ($bug->component_id, $bug->component_id);

  # notify when the product/component is switch from one being watched
  if (@$diffs) {

    # we need the product to process the component, so scan for that first
    my $product;
    foreach my $ra (@$diffs) {
      next if !(exists $ra->{'old'} && exists $ra->{'field_name'});
      if ($ra->{'field_name'} eq 'product') {
        $product = Bugzilla::Product->new({name => $ra->{'old'}, cache => 1});
        $oldProductId = $product->id;
      }
    }
    if (!$product) {
      $product = Bugzilla::Product->new({id => $oldProductId, cache => 1});
    }
    foreach my $ra (@$diffs) {
      next if !(exists $ra->{'old'} && exists $ra->{'field_name'});
      if ($ra->{'field_name'} eq 'component') {
        my $component
          = Bugzilla::Component->new({
          name => $ra->{'old'}, product => $product, cache => 1
          });
        $oldComponentId = $component->id;
      }
    }
  }

  # add component watchers
  my $dbh = Bugzilla->dbh;
  my $sth = $dbh->prepare("
        SELECT user_id
          FROM component_watch
         WHERE ((product_id = ? OR product_id = ?) AND component_id IS NULL)
               OR (component_id = ? OR component_id = ?)
        UNION
        SELECT user_id
          FROM component_watch
               INNER JOIN components ON components.product_id = component_watch.product_id
         WHERE component_prefix IS NOT NULL
               AND (component_watch.product_id = ? OR component_watch.product_id = ?)
               AND components.name LIKE @{[$dbh->sql_string_concat('component_prefix', q{'%'})]}
               AND (components.id = ? OR components.id = ?)
    ");
  $sth->execute(
    $oldProductId, $newProductId, $oldComponentId, $newComponentId,
    $oldProductId, $newProductId, $oldComponentId, $newComponentId,
  );
  while (my ($uid) = $sth->fetchrow_array) {
    if (!exists $recipients->{$uid}) {
      $recipients->{$uid}->{+REL_COMPONENT_WATCHER}
        = Bugzilla::BugMail::BIT_WATCHING();
    }
  }

  # add component watchers from watch-users
  my $uidList = join(',', keys %$recipients);
  $sth = $dbh->prepare("
        SELECT component_watch.user_id
          FROM components
               INNER JOIN component_watch ON component_watch.component_id = components.id
         WHERE components.watch_user in ($uidList)
    ");
  $sth->execute();
  while (my ($uid) = $sth->fetchrow_array) {
    if (!exists $recipients->{$uid}) {
      $recipients->{$uid}->{+REL_COMPONENT_WATCHER}
        = Bugzilla::BugMail::BIT_WATCHING();
    }
  }

  # add watch-users from component watchers
  $sth = $dbh->prepare("
        SELECT watch_user
          FROM components
         WHERE (id = ? OR id = ?)
               AND (watch_user IS NOT NULL)
    ");
  $sth->execute($oldComponentId, $newComponentId);
  while (my ($uid) = $sth->fetchrow_array) {
    if (!exists $recipients->{$uid}) {
      $recipients->{$uid}->{+REL_COMPONENT_WATCHER} = Bugzilla::BugMail::BIT_DIRECT();
    }
  }
}

sub bugmail_relationships {
  my ($self, $args) = @_;
  my $relationships = $args->{relationships};
  $relationships->{+REL_COMPONENT_WATCHER} = 'Component-Watcher';
}

#
# db
#

sub _getWatches {
  my ($user, $watch_id) = @_;
  my $dbh = Bugzilla->dbh;

  $watch_id = (defined $watch_id && $watch_id =~ /^(\d+)$/) ? $1 : undef;

  my $sth = $dbh->prepare("
        SELECT id, product_id, component_id, component_prefix
          FROM component_watch
         WHERE user_id = ?" . ($watch_id ? " AND id = ?" : ""));
  $watch_id ? $sth->execute($user->id, $watch_id) : $sth->execute($user->id);

  my @watches;
  while (my ($id, $productId, $componentId, $prefix) = $sth->fetchrow_array) {
    my $product = Bugzilla::Product->new({id => $productId, cache => 1});
    next unless $product && $user->can_access_product($product);

    my %watch = (
      id               => $id,
      product          => $product,
      product_name     => $product->name,
      component_name   => '',
      component_prefix => $prefix,
    );
    if ($componentId) {
      my $component = Bugzilla::Component->new({id => $componentId, cache => 1});
      next unless $component;
      $watch{'component'}      = $component;
      $watch{'component_name'} = $component->name;
    }

    push @watches, \%watch;
  }

  if ($watch_id) {
    return $watches[0] || {};
  }

  @watches = sort {
         $a->{'product_name'} cmp $b->{'product_name'}
      || $a->{'component_name'} cmp $b->{'component_name'}
      || $a->{'component_prefix'} cmp $b->{'component_prefix'}
  } @watches;

  return \@watches;
}

sub _getUserWatches {
  my ($user) = @_;
  my $dbh = Bugzilla->dbh;

  my $sth = $dbh->prepare("
        SELECT components.product_id, components.id as component, profiles.login_name
          FROM watch
               INNER JOIN components ON components.watch_user = watched
               INNER JOIN profiles ON profiles.userid = watched
         WHERE watcher = ?
    ");
  $sth->execute($user->id);
  my @watches;
  while (my ($productId, $componentId, $login) = $sth->fetchrow_array) {
    my $product = Bugzilla::Product->new({id => $productId, cache => 1});
    next unless $product && $user->can_access_product($product);

    my %watch = (
      product   => $product,
      component => Bugzilla::Component->new({id => $componentId, cache => 1}),
      user      => Bugzilla::User->check($login),
    );
    push @watches, \%watch;
  }

  @watches = sort {
         $a->{'product'}->name cmp $b->{'product'}->name
      || $a->{'component'}->name cmp $b->{'component'}->name
  } @watches;

  return \@watches;
}

sub _addProductWatch {
  my ($user, $product) = @_;
  my $dbh = Bugzilla->dbh;

  my $sth = $dbh->prepare("
        SELECT 1
          FROM component_watch
         WHERE user_id = ? AND product_id = ? AND component_id IS NULL
    ");
  $sth->execute($user->id, $product->id);
  return if $sth->fetchrow_array;

  $sth = $dbh->prepare("
        DELETE FROM component_watch
              WHERE user_id = ? AND product_id = ?
    ");
  $sth->execute($user->id, $product->id);

  $sth = $dbh->prepare("
        INSERT INTO component_watch(user_id, product_id)
             VALUES (?, ?)
    ");
  $sth->execute($user->id, $product->id);

  return _getWatches($user, $dbh->bz_last_key());
}

sub _addComponentWatch {
  my ($user, $component) = @_;
  my $dbh = Bugzilla->dbh;

  my $sth = $dbh->prepare("
        SELECT 1
          FROM component_watch
         WHERE user_id = ?
               AND (component_id = ?  OR (product_id = ? AND component_id IS NULL))
    ");
  $sth->execute($user->id, $component->id, $component->product_id);
  return if $sth->fetchrow_array;

  $sth = $dbh->prepare("
        INSERT INTO component_watch(user_id, product_id, component_id)
             VALUES (?, ?, ?)
    ");
  $sth->execute($user->id, $component->product_id, $component->id);

  return _getWatches($user, $dbh->bz_last_key());
}

sub _addPrefixWatch {
  my ($user, $product, $prefix) = @_;
  my $dbh = Bugzilla->dbh;

  trick_taint($prefix);
  my $sth = $dbh->prepare("
        SELECT 1
          FROM component_watch
         WHERE user_id = ?
               AND (
                   (product_id = ? AND component_prefix = ?)
                   OR (product_id = ? AND component_id IS NULL)
               )
    ");
  $sth->execute($user->id, $product->id, $prefix, $product->id);
  return if $sth->fetchrow_array;

  $sth = $dbh->prepare("
        INSERT INTO component_watch(user_id, product_id, component_prefix)
             VALUES (?, ?, ?)
    ");
  $sth->execute($user->id, $product->id, $prefix);
}

sub _deleteWatch {
  my ($user, $id) = @_;
  my $dbh = Bugzilla->dbh;

  detaint_natural($id) || ThrowCodeError("component_watch_invalid_id");

  return $dbh->do("DELETE FROM component_watch WHERE id=? AND user_id=?",
    undef, $id, $user->id);
}

sub _addDefaultSettings {
  my ($user) = @_;
  my $dbh = Bugzilla->dbh;

  my $sth = $dbh->prepare("
        SELECT 1
          FROM email_setting
         WHERE user_id = ? AND relationship = ?
    ");
  $sth->execute($user->id, REL_COMPONENT_WATCHER);
  return if $sth->fetchrow_array;

  my @defaultEvents = (EVT_OTHER, EVT_COMMENT,
    EVT_ATTACHMENT,      EVT_ATTACHMENT_DATA,
    EVT_PROJ_MANAGEMENT, EVT_OPENED_CLOSED,
    EVT_KEYWORD,         EVT_DEPEND_BLOCK,
    EVT_BUG_CREATED,
  );
  foreach my $event (@defaultEvents) {
    $dbh->do("INSERT INTO email_setting(user_id,relationship,event) VALUES (?,?,?)",
      undef, $user->id, REL_COMPONENT_WATCHER, $event);
  }
}

sub reorg_move_component {
  my ($self, $args) = @_;
  my $new_product = $args->{new_product};
  my $component   = $args->{component};

  Bugzilla->dbh->do(
    "UPDATE component_watch SET product_id=? WHERE component_id=?",
    undef, $new_product->id, $component->id,);
}

sub sanitycheck_check {
  my ($self, $args) = @_;
  my $status = $args->{status};

  $status->('component_watching_check');

  my ($count) = Bugzilla->dbh->selectrow_array("
        SELECT COUNT(*)
          FROM component_watch
         INNER JOIN components ON components.id = component_watch.component_id
         WHERE component_watch.product_id <> components.product_id
    ");
  if ($count) {
    $status->('component_watching_alert', undef, 'alert');
    $status->('component_watching_repair');
  }
}

sub sanitycheck_repair {
  my ($self, $args) = @_;
  return unless Bugzilla->cgi->param('component_watching_repair');

  my $status = $args->{'status'};
  my $dbh    = Bugzilla->dbh;
  $status->('component_watching_repairing');

  my $rows = $dbh->selectall_arrayref("
        SELECT DISTINCT component_watch.product_id AS bad_product_id,
               components.product_id AS good_product_id,
               component_watch.component_id
          FROM component_watch
         INNER JOIN components ON components.id = component_watch.component_id
         WHERE component_watch.product_id <> components.product_id
        ", {Slice => {}});
  foreach my $row (@$rows) {
    $dbh->do("
            UPDATE component_watch
               SET product_id=?
             WHERE product_id=? AND component_id=?
            ", undef, $row->{good_product_id}, $row->{bad_product_id},
      $row->{component_id},);
  }
}

#
# webservice
#

sub webservice {
  my ($self, $args) = @_;
  $args->{dispatch}->{ComponentWatching}
    = "Bugzilla::Extension::ComponentWatching::WebService";
}

__PACKAGE__->NAME;
