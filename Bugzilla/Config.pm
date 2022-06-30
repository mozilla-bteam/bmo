# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object Exporter);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Logging;

use Module::Runtime qw(require_module);
use Safe;
use Try::Tiny;

%Bugzilla::Config::EXPORT_TAGS
  = (admin => [qw(SetParam write_params)],);
Exporter::export_ok_tags('admin');

###############################
####    Initialization     ####
###############################

sub new {
  my $invocant = shift;
  my $class    = ref($invocant) || $invocant;

  my $cache = Bugzilla->request_cache;
  if ($cache->{params_obj}) {
    return $cache->{params_obj};
  }

  my $self = {params => {}};
  bless($self, $class);

  if (my $cached_params = Bugzilla->memcached->get_params()) {
    $self->{params} = $cached_params;
  }
  else {
    try {
      my $dbh  = Bugzilla->dbh;
      my $rows = $dbh->selectall_arrayref('SELECT name, value FROM params');
      foreach my $row (@$rows) {
        my ($name, $value) = @$row;
        $self->{params}->{$name} = $value;
      }
    }
    catch {
      WARN("Database not yet available: $_")
        unless Bugzilla->usage_mode == USAGE_MODE_CMDLINE;
      # Load defaults if database is unavailable
      my $defs = $self->_load_param_defs();
      foreach my $key (keys %{$defs}) {
        $self->{params}->{$key} = $defs->{$key}->{default};
      }
    };
  }

  $cache->{params_obj} = $self;

  return $self;
}

###############################
####       Setters         ####
###############################

sub set_param {
  my ($self, $name, $value) = @_;

  die "Unknown param $name" unless (exists $self->{params}->{$name});

  # Validate the value
  # XXX - This runs the checks. Which would be good, except that
  # check_shadowdb creates the database as a side effect, and so the
  # checker fails the second time around...
  my $def = $self->_load_param_defs->{$name};
  if ($name ne 'shadowdb' && exists $def->{'checker'}) {
    my $err = $def->{'checker'}->($value, $def);
    die "Param $name is not valid: $err" unless $err eq '';
  }

  $self->{params}->{$name} = $value;

  # Force Bugzilla->params to see the new change
  delete Bugzilla->request_cache->{params};
}

sub update {
  my ($self, $params) = @_;
  $params ||= $self->{params};

  try {
    my $dbh = Bugzilla->dbh;
    foreach my $key (keys %{$params}) {
      my $new_value = $params->{$key} || '';
      if ($dbh->selectrow_array('SELECT 1 FROM params WHERE name = ?', undef, $key)) {
        $dbh->do('UPDATE params SET value = ? WHERE name = ?', undef, $new_value, $key);
      }
      else {
        $dbh->do('INSERT INTO params (name, value) VALUES (?, ?)',
          undef, $key, $new_value);
      }
    }

    # And now we have to reset the params cache
    Bugzilla->memcached->set_params($params);
    delete Bugzilla->request_cache->{params};
    delete Bugzilla->request_cache->{params_obj};
    $self->{params} = $params;
  }
  catch {
    WARN("Database not yet available: $_")
      unless Bugzilla->usage_mode == USAGE_MODE_CMDLINE;
  };
}

sub migrate_params {
  my ($self, $params) = @_;
  my $answer = Bugzilla->installation_answers;
  my $param  = $self->params_as_hash;

  # Migrate old file based parameters to the database
  my $datadir = bz_locations()->{'datadir'};
  if (-e "$datadir/params") {

    # Read in the old data/params values
    my $s = Safe->new;
    $s->rdo("$datadir/params");
    die "Error reading $datadir/params: $!"    if $!;
    die "Error evaluating $datadir/params: $@" if $@;
    my %file_params = %{$s->varglob('param')};

    WARN('Migrating old parameters from data/params to database');
    foreach my $key (keys %file_params) {
      $param->{$key} = $file_params{$key};
    }

    WARN('Backing up old params file');
    rename("$datadir/params", "$datadir/params.old")
      or die "Rename params file failed: $!";
  }

  # --- UPDATE OLD PARAMS ---

  my %new_params;

  # Change from usebrowserinfo to defaultplatform/defaultopsys combo
  if (exists $param->{'usebrowserinfo'}) {
    if (!$param->{'usebrowserinfo'}) {
      if (!exists $param->{'defaultplatform'}) {
        $new_params{'defaultplatform'} = 'Other';
      }
      if (!exists $param->{'defaultopsys'}) {
        $new_params{'defaultopsys'} = 'Other';
      }
    }
  }

  # Change from a boolean for quips to multi-state
  if (exists $param->{'usequip'} && !exists $param->{'enablequips'}) {
    $new_params{'enablequips'} = $param->{'usequip'} ? 'on' : 'off';
  }

  # Change from old product groups to controls for group_control_map
  # 2002-10-14 bug 147275 bugreport@peshkin.net
  if (exists $param->{'usebuggroups'} && !exists $param->{'makeproductgroups'}) {
    $new_params{'makeproductgroups'} = $param->{'usebuggroups'};
  }

  # Modularise auth code
  if (exists $param->{'useLDAP'} && !exists $param->{'loginmethod'}) {
    $new_params{'loginmethod'} = $param->{'useLDAP'} ? "LDAP" : "DB";
  }

  # set verify method to whatever loginmethod was
  if (exists $param->{'loginmethod'} && !exists $param->{'user_verify_class'}) {
    $new_params{'user_verify_class'} = $param->{'loginmethod'};
  }

  # Remove quip-display control from parameters
  # and give it to users via User Settings (Bug 41972)
  if (exists $param->{'enablequips'}
    && !exists $param->{'quip_list_entry_control'})
  {
    my $new_value;
    ($param->{'enablequips'} eq 'on')       && do { $new_value = 'open'; };
    ($param->{'enablequips'} eq 'approved') && do { $new_value = 'moderated'; };
    ($param->{'enablequips'} eq 'frozen')   && do { $new_value = 'closed'; };
    ($param->{'enablequips'} eq 'off')      && do { $new_value = 'closed'; };
    $new_params{'quip_list_entry_control'} = $new_value;
  }

  # Old mail_delivery_method choices contained no uppercase characters
  if (exists $param->{'mail_delivery_method'}
    && $param->{'mail_delivery_method'} !~ /[A-Z]/)
  {
    my $method      = $param->{'mail_delivery_method'};
    my %translation = (
      'sendmail' => 'Sendmail',
      'smtp'     => 'SMTP',
      'qmail'    => 'Qmail',
      'testfile' => 'Test',
      'none'     => 'None'
    );
    $param->{'mail_delivery_method'} = $translation{$method};
  }

  # Convert the old "ssl" parameter to the new "ssl_redirect" parameter.
  # Both "authenticated sessions" and "always" turn on "ssl_redirect"
  # when upgrading.
  if (exists $param->{'ssl'} and $param->{'ssl'} ne 'never') {
    $new_params{'ssl_redirect'} = 1;
  }

  # "specific_search_allow_empty_words" has been renamed to
  # "search_allow_no_criteria".
  if (exists $param->{'specific_search_allow_empty_words'}) {
    $new_params{'search_allow_no_criteria'}
      = $param->{'specific_search_allow_empty_words'};
  }

  # --- DEFAULTS FOR NEW PARAMS ---

  my %params = %{$self->_load_param_defs};
  foreach my $name (keys %params) {
    my $item = $params{$name};

    # If a new param was added since the last time we ran migrate_params,
    # use either the value from new_params, if exists, or use the default.
    if (!exists $param->{$name}) {
      print "New parameter: $name\n";
      if (exists $new_params{$name}) {
        $param->{$name} = $new_params{$name};
      }
      else {
        $param->{$name} = $item->{'default'};
      }
    }

    # If an answers file was passed to checksetup.pl then override the
    # current values with the ones in the answers file.
    if (exists $answer->{$name}) {
      $param->{$name} = $answer->{$name};
    }

    # Check all values to make sure they are still valid if a checker
    # function exists.
    my $checker = $item->{'checker'};
    my $updater = $item->{'updater'};
    if ($checker) {
      my $error = $checker->($param->{$name}, $item);
      if ($error && $updater) {
        my $new_val = $updater->($param->{$name});
        $param->{$name} = $new_val unless $checker->($new_val, $item);
      }
      elsif ($error) {
        WARN("Invalid parameter: $name");
      }
    }
  }

  # Return deleted params and values so that checksetup.pl has a chance
  # to convert old params to new data.
  my %oldparams;
  foreach my $item (keys %$param) {
    if (!exists $params{$item}) {
      $oldparams{$item} = delete $param->{$item};
    }
  }

  # Generate unique Duo integration secret key
  if ($param->{duo_akey} eq '') {
    require Bugzilla::Util;
    $param->{duo_akey} = Bugzilla::Util::generate_random_password(40);
  }

  if ( ON_WINDOWS
    && !-e SENDMAIL_EXE
    && $param->{'mail_delivery_method'} eq 'Sendmail')
  {
    my $smtp = $answer->{'SMTP_SERVER'};
    if (!$smtp) {
      print "\nBugzilla requires an SMTP server to function on",
        " Windows.\nPlease enter your SMTP server's hostname: ";
      $smtp = <STDIN>;
      chomp $smtp;
      if ($smtp) {
        $param->{'smtpserver'} = $smtp;
      }
      else {
        print "\nWarning: No SMTP Server provided, defaulting to", " localhost\n";
      }
    }

    $param->{'mail_delivery_method'} = 'SMTP';
  }

  $self->update($param);

  return %oldparams;
}

###############################
####      Accessors        ####
###############################

sub get_param      { return $_[0]->{params}->{$_[1]}; }
sub params_as_hash { return $_[0]->{params}; }

sub param_panels {
  my ($self) = @_;

  return $self->{param_panels} if exists $self->{param_panels};

  $self->{param_panels} = {};
  my $libpath = bz_locations()->{'libpath'};
  foreach my $item ((glob "$libpath/Bugzilla/Config/*.pm")) {
    $item =~ m#/([^/]+)\.pm$#;
    my $module = $1;
    $self->{param_panels}->{$module} = "Bugzilla::Config::$module"
      unless $module eq 'Common';
  }

  # Now check for any hooked params
  Bugzilla::Hook::process('config_add_panels', {panel_modules => $self->{param_panels}});

  return $self->{param_panels};
}

###############################
####      Private          ####
###############################

sub _load_param_defs {
  my ($self) = @_;

  return $self->{param_defs} if exists $self->{params_def};

  my $panels = $self->param_panels;
  my %hook_panels;
  foreach my $panel (keys %$panels) {
    my $module = $panels->{$panel};
    require_module($module);
    my @new_param_list = $module->get_param_list();
    $hook_panels{lc($panel)} = {params => \@new_param_list};
  }

  # This hook is also called in editparams.cgi. This call here is required
  # to make set_param work.
  Bugzilla::Hook::process('config_modify_panels', {panels => \%hook_panels});

  foreach my $panel (keys %hook_panels) {
    foreach my $item (@{$hook_panels{$panel}->{params}}) {
      $self->{param_defs}->{$item->{name}} = $item;
    }
  }

  return $self->{param_defs};
}

###############################
####     Legacy Methods    ####
###############################

sub SetParam {
  my ($name, $value) = @_;
  __PACKAGE__->new->set_param($name, $value);
}

sub write_params {
  __PACKAGE__->new->update(@_);
}

1;
