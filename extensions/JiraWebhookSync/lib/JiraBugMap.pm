# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::JiraWebhookSync::JiraBugMap;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural trim);

use JSON::MaybeXS qw(decode_json);
use List::Util qw(none);
use Mojo::URL;
use Scalar::Util qw(blessed);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'jira_bug_map';

use constant DB_COLUMNS => qw(
  id
  bug_id
  jira_id
  jira_project_key
);

use constant UPDATE_COLUMNS => qw(
  jira_id
  jira_project_key
);

use constant VALIDATORS => {
  bug_id           => \&_check_bug_id,
  jira_id          => \&_check_jira_id,
  jira_project_key => \&_check_jira_project_key,
};

use constant VALIDATOR_DEPENDENCIES => {
  jira_id => ['jira_project_key'],
};

###############################
####      Accessors      ######
###############################

sub bug_id           { return $_[0]->{bug_id}; }
sub jira_id          { return $_[0]->{jira_id}; }
sub jira_project_key { return $_[0]->{jira_project_key}; }

sub bug {
  my ($self) = @_;
  return $self->{bug} //= Bugzilla::Bug->new($self->bug_id);
}

###############################
####       Mutators       #####
###############################

sub set_jira_id          { $_[0]->set('jira_id',          $_[1]); }
sub set_jira_project_key { $_[0]->set('jira_project_key', $_[1]); }

###############################
####      Validators      #####
###############################

sub _check_bug_id {
  my ($invocant, $bug_id) = @_;

  $bug_id = trim($bug_id);
  detaint_natural($bug_id) || ThrowUserError('jira_bug_id_required');

  return $bug_id;
}

sub _check_jira_id {
  my ($invocant, $jira_id) = @_;

  $jira_id = trim($jira_id);
  $jira_id || ThrowUserError('jira_id_required');

  return $jira_id;
}

sub _check_jira_project_key {
  my ($invocant, $project_key) = @_;

  $project_key = trim($project_key);
  $project_key || ThrowUserError('jira_project_key_required');

  return $project_key;
}

###############################
####      Methods         #####
###############################

# Get mapping by bug_id
sub get_by_bug_id {
  my ($class, $bug_id) = @_;

  return $class->new({
    condition => 'bug_id = ?',
    values    => [$bug_id],
  });
}

# Get mapping by jira_id
sub get_by_jira_id {
  my ($class, $jira_id) = @_;

  return $class->new({
    condition => 'jira_id = ?',
    values    => [$jira_id],
  });
}

# Extract Jira project key from a Jira URL or ID
sub extract_jira_info {
  my ($class, $see_also) = @_;
  my $params = Bugzilla->params;

  # Only return values if the hostname matches
  my $url = Mojo::URL->new($see_also);
  return undef if $url->host ne $params->{jira_webhook_sync_hostname};

  # Match patterns like:
  # - https://jira.example.com/PROJ-123
  # - https://jira.example.com/browse/PROJ-123
  # - https://jira.example.com/projects/PROJ/issues/PROJ-123

  my ($project_key, $jira_id);

  if ($url->path =~ m{^/?([[:upper:]]+)-\d+$}) {

    # Direct format: PROJ-123
    $jira_id     = $url->path;
    $project_key = $1;
  }
  elsif ($url->path =~ m{/browse/([[:upper:]]+-\d+)}) {

    # URL format: /browse/PROJ-123
    $jira_id = $1;
    ($project_key) = $jira_id =~ /^([[:upper:]]+)-/;
  }
  elsif ($url->path =~ m{/issues/([[:upper:]]+-\d+)}) {

    # URL format: /issues/PROJ-123
    $jira_id = $1;
    ($project_key) = $jira_id =~ /^([[:upper:]]+)-/;
  }

  return undef unless $jira_id && $project_key;

  # Return undef if project key is not in configured list
  if (none { $_ eq $project_key }
    @{decode_json($params->{jira_webhook_sync_project_keys} || '[]')})
  {
    return undef;
  }

  return ($jira_id, $project_key);
}

1;
