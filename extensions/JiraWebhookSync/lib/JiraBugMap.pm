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
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Util qw(detaint_natural trim);

use JSON::MaybeXS qw(decode_json);
use List::Util qw(none);
use URI;
use Scalar::Util qw(blessed);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'jira_bug_map';

use constant DB_COLUMNS => qw(
  id
  bug_id
  jira_project_key
  jira_url
);

use constant UPDATE_COLUMNS => qw(
  jira_url
  jira_project_key
);

use constant VALIDATORS => {
  bug_id           => \&_check_bug_id,
  jira_url         => \&_check_jira_url,
  jira_project_key => \&_check_jira_project_key,
};

use constant VALIDATOR_DEPENDENCIES => {
  jira_url => ['jira_project_key'],
};

###############################
####      Accessors      ######
###############################

sub bug_id           { return $_[0]->{bug_id}; }
sub jira_url         { return $_[0]->{jira_url}; }
sub jira_project_key { return $_[0]->{jira_project_key}; }

sub bug {
  my ($self) = @_;
  return $self->{bug} //= Bugzilla::Bug->new($self->bug_id);
}

###############################
####       Mutators       #####
###############################

sub set_jira_url         { $_[0]->set('jira_url',         $_[1]); }
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

sub _check_jira_url {
  my ($invocant, $jira_url) = @_;

  $jira_url = trim($jira_url);
  $jira_url || ThrowUserError('jira_url_required');

  $jira_url = URI->new($jira_url);

  if ( !$jira_url
    || ($jira_url->scheme ne 'http' && $jira_url->scheme ne 'https')
    || !$jira_url->authority
    || length($jira_url->path) > MAX_BUG_URL_LENGTH)
  {
    ThrowUserError('jira_url_required');
  }

  # always https
  $jira_url->scheme('https');

  return $jira_url->as_string;
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

# Extract Jira project key from a Jira URL
sub extract_jira_project_key {
  my ($class, $see_also) = @_;
  my $params = Bugzilla->params;

  # Match pattern
  # https://jira.example.com/browse/PROJ-123
  my $url = URI->new($see_also);
  my $project_key = undef;
  if ($url->path =~ m{^/browse/([[:upper:]]+)-\d+$}) {
    $project_key = $1;
    return undef if !$project_key;

    # Return undef if project key is not in configured list
    if (none { $_ eq $project_key }
      @{decode_json($params->{jira_webhook_sync_project_keys} || '[]')})
    {
      return undef;
    }
  }

  return $project_key;
}

1;
