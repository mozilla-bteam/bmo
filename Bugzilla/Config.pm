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

use base qw(Exporter);

use Bugzilla::Config::Param;
use Bugzilla::Constants;
use Bugzilla::Hook;
use Bugzilla::Logging;

use Module::Runtime qw(require_module);
use Safe;
use Try::Tiny;

# Don't export localvars by default - people should have to explicitly
# ask for it, as a (probably futile) attempt to stop code using it
# when it shouldn't
%Bugzilla::Config::EXPORT_TAGS
  = (admin => [qw(update_params SetParam write_params)],);
Exporter::export_ok_tags('admin');

# INITIALIZATION CODE
# Perl throws a warning if we use bz_locations() directly after do.
our %params;

# Load in the param definitions
sub _load_params {
  my $panels = param_panels();
  my %hook_panels;
  foreach my $panel (keys %$panels) {
    my $module = $panels->{$panel};
    require_module($module);
    my @new_param_list = $module->get_param_list();
    $hook_panels{lc($panel)} = {params => \@new_param_list};
  }

  # This hook is also called in editparams.cgi. This call here is required
  # to make SetParam work.
  Bugzilla::Hook::process('config_modify_panels', {panels => \%hook_panels});

  foreach my $panel (keys %hook_panels) {
    foreach my $item (@{$hook_panels{$panel}->{params}}) {
      $params{$item->{'name'}} = $item;
    }
  }
}

# END INIT CODE

# Subroutines go here

sub param_panels {
  my $param_panels = {};
  my $libpath      = bz_locations()->{'libpath'};
  foreach my $item ((glob "$libpath/Bugzilla/Config/*.pm")) {
    $item =~ m#/([^/]+)\.pm$#;
    my $module = $1;
    next if $module eq 'Param';    # Skip the module used for loading params from DB
    $param_panels->{$module} = "Bugzilla::Config::$module"
      unless $module eq 'Common';
  }

  # Now check for any hooked params
  Bugzilla::Hook::process('config_add_panels', {panel_modules => $param_panels});
  return $param_panels;
}

sub SetParam {
  my ($name, $value) = @_;

  # Initialize the parameters if none exist (first time) and reload
  update_params() if !keys %{Bugzilla->params};

  _load_params unless %params;
  die "Unknown param $name" unless (exists $params{$name});

  my $entry = $params{$name};

  # sanity check the value

  # XXX - This runs the checks. Which would be good, except that
  # check_shadowdb creates the database as a side effect, and so the
  # checker fails the second time around...
  if ($name ne 'shadowdb' && exists $entry->{'checker'}) {
    my $err = $entry->{'checker'}->($value, $entry);
    die "Param $name is not valid: $err" unless $err eq '';
  }

  Bugzilla->params->{$name} = $value;
}

sub update_params {
  my ($params) = @_;
  my $answer = Bugzilla->installation_answers;

  my $param = read_params();

  # Check to see if we need to migrate old file based parameters
  $param = _migrate_file_parameters($param);

  my %new_params;

  # If we didn't return any param values, then this is a new installation.
  my $new_install = !(keys %$param);

  # --- UPDATE OLD PARAMS ---

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

  # "specific_search_allow_empty_words" has been renamed to "search_allow_no_criteria".
  if (exists $param->{'specific_search_allow_empty_words'}) {
    $new_params{'search_allow_no_criteria'}
      = $param->{'specific_search_allow_empty_words'};
  }

  # --- DEFAULTS FOR NEW PARAMS ---

  _load_params unless %params;
  foreach my $name (keys %params) {
    my $item = $params{$name};
    unless (exists $param->{$name}) {
      print "New parameter: $name\n" unless $new_install;
      if (exists $new_params{$name}) {
        $param->{$name} = $new_params{$name};
      }
      elsif (exists $answer->{$name}) {
        $param->{$name} = $answer->{$name};
      }
      else {
        $param->{$name} = $item->{'default'};
      }
    }
    else {
      my $checker = $item->{'checker'};
      my $updater = $item->{'updater'};
      if ($checker) {
        my $error = $checker->($param->{$name}, $item);
        if ($error && $updater) {
          my $new_val = $updater->($param->{$name});
          $param->{$name} = $new_val unless $checker->($new_val, $item);
        }
        elsif ($error) {
          warn "Invalid parameter: $name\n";
        }
      }
    }
  }

  # Generate unique Duo integration secret key
  if ($param->{duo_akey} eq '') {
    require Bugzilla::Util;
    $param->{duo_akey} = Bugzilla::Util::generate_random_password(40);
  }

  $param->{'utf8'} = 1 if $new_install;

  my %oldparams;

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

  write_params($param);

  # Return deleted params and values so that checksetup.pl has a chance
  # to convert old params to new data.
  return %oldparams;
}

sub write_params {
  my ($param_data) = @_;
  $param_data ||= Bugzilla->params;

  try {
    my $dbh = Bugzilla->dbh;
    foreach my $key (keys %{$param_data}) {
      if (my $param = Bugzilla::Config::Param->new({name => $key})) {
        my $value = $param_data->{$key} || ($param->is_numeric ? 0 : '');
        if (($param->is_numeric && $value != $param->value) || $value ne $param->value)
        {
          $param->set_value($value);
          $param->update();
        }
      }
      else {
        my $value = $param_data->{$key} || '';
        Bugzilla::Config::Param->create({name => $key, value => $value});
      }
    }
  }
  catch {
    WARN("Database not available: $_");
  };

  # And now we have to reset the params cache
  Bugzilla->memcached->set_params($param_data);
  Bugzilla->request_cache->{params} = $param_data;
}

sub read_params {
  my %params;

  try {
    my @all_params = Bugzilla::Config::Param->get_all();
    if (@all_params) {
      foreach my $param (@all_params) {
        $params{$param->name} = $param->value;
      }
    }
  }
  catch {
    if ($ENV{'SERVER_SOFTWARE'}) {
      FATAL('Parameters have not yet been written to the database.'
          . ' You probably need to run checksetup.pl.');
    }
  };

  return \%params;
}

sub _migrate_file_parameters {
  my $params = shift;

  # Return if the old data/params file has already been removed
  my $datadir = bz_locations()->{'datadir'};
  return if !-f "$datadir/params";

  # Read in the old data/params values
  my $s = Safe->new;
  $s->rdo("$datadir/params");
  die "Error reading $datadir/params: $!"    if $!;
  die "Error evaluating $datadir/params: $@" if $@;
  my $file_params = $s->varglob('param');
  return if !%{$file_params};

  WARN('Migrating old parameters from data/params to database');

  # Insert the key/values into the params table
  foreach my $key (keys %{$file_params}) {
    $params->{$key} = $file_params->{$key} || '';
  }

  # Move the params file so we do not run this again
  rename("$datadir/params", "$datadir/params.old")
    or die "Rename params file failed: $!";

  return $params;
}

1;

__END__

=head1 NAME

Bugzilla::Config - Configuration parameters for Bugzilla

=head1 SYNOPSIS

  # Administration functions
  use Bugzilla::Config qw(:admin);

  update_params();
  SetParam($param, $value);
  write_params();

=head1 DESCRIPTION

This package contains ways to access Bugzilla configuration parameters.

=head1 FUNCTIONS

=head2 Parameters

Parameters can be set, retrieved, and updated.

=over 4

=item C<SetParam($name, $value)>

Sets the param named $name to $value. Values are checked using the checker
function for the given param if one exists.

=item C<update_params()>

Updates the parameters, by transitioning old params to new formats, setting
defaults for new params, and removing obsolete ones. Used by F<checksetup.pl>
in the process of an installation or upgrade.

Prints out information about what it's doing, if it makes any changes.

May prompt the user for input, if certain required parameters are not
specified.

=item C<write_params($params)>

Description: Writes the parameters to disk.

Params:      C<$params> (optional) - A hashref to write to the DB
               instead of C<Bugzilla->params>. Used only by
               C<update_params>.

Returns:     nothing

=back
