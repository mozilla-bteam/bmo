# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connectors;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Constants;
use Bugzilla::Util qw(trick_taint);
use File::Basename;
use Try::Tiny;

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self, $class);

  $self->{names}   = [];
  $self->{objects} = {};
  $self->{path}    = bz_locations->{'extensionsdir'} . '/Push/lib/Connector';

  foreach my $file (glob($self->{path} . '/*.pm')) {
    my $name = basename($file);
    $name =~ s/\.pm$//;
    next if $name eq 'Base';
    if (length($name) > 32) {
      WARN("Ignoring connector '$name': Name longer than 32 characters");
    }
    push @{$self->{names}}, $name;
    TRACE("Found connector '$name'");
  }

  return $self;
}

sub _load {
  my ($self) = @_;
  return if scalar keys %{$self->{objects}};

  foreach my $name (@{$self->{names}}) {
    next if exists $self->{objects}->{$name};
    my $file = $self->{path} . "/$name.pm";
    trick_taint($file);
    require $file;
    my $package = "Bugzilla::Extension::Push::Connector::$name";

    TRACE("Loading connector '$name'");
    my $old_error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);
    try {
      my $connector = $package->new();
      $connector->load_config();
      $self->{objects}->{$name} = $connector;
    }
    catch {
      ERROR("Connector '$name' failed to load: " . clean_error($_));
    };
    Bugzilla->error_mode($old_error_mode);
  }
}

sub stop {
  my ($self) = @_;
  foreach my $connector ($self->list) {
    next unless $connector->enabled;
    TRACE("Stopping '" . $connector->name . "'");
    try {
      $connector->stop();
    }
    catch {
      ERROR(
        "Connector '" . $connector->name . "' failed to stop: " . clean_error($_));
    };
  }
}

sub reload {
  my ($self) = @_;
  $self->stop();
  $self->{objects} = {};
  $self->_load();
}

sub names {
  my ($self) = @_;
  return @{$self->{names}};
}

sub list {
  my ($self) = @_;
  $self->_load();
  return sort { $a->name cmp $b->name } values %{$self->{objects}};
}

sub exists {
  my ($self, $name) = @_;
  $self->by_name($name) ? 1 : 0;
}

sub by_name {
  my ($self, $name) = @_;
  $self->_load();
  return unless exists $self->{objects}->{$name};
  return $self->{objects}->{$name};
}

1;

