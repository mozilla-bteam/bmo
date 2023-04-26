# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Repository;

use 5.10.1;
use Moo;
use Types::Standard -all;

use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Project;
use Bugzilla::Extension::PhabBugz::Types qw(:types);
use Bugzilla::Extension::PhabBugz::Util qw(request);

#########################
#    Initialization     #
#########################

has id              => (is => 'ro',   isa => Int);
has phid            => (is => 'ro',   isa => Str);
has type            => (is => 'ro',   isa => Str);
has name            => (is => 'ro',   isa => Str);
has description     => (is => 'ro',   isa => Maybe [Str]);
has vcs             => (is => 'ro',   isa => Str);
has status          => (is => 'ro',   isa => Str);
has call_sign       => (is => 'ro',   isa => Str);
has short_name      => (is => 'ro',   isa => Str);
has default_branch  => (is => 'ro',   isa => Str);
has creation_ts     => (is => 'ro',   isa => Str);
has modification_ts => (is => 'ro',   isa => Str);
has view_policy     => (is => 'ro',   isa => Str);
has edit_policy     => (is => 'ro',   isa => Str);
has push_policy     => (is => 'ro',   isa => Str);
has projects_raw    => (is => 'ro',   isa => Dict [projectPHIDs => ArrayRef [Str]]);
has projects        => (is => 'lazy', isa => ArrayRef [Project]);

sub new_from_query {
  my ($class, $params) = @_;

  my $data
    = {queryKey => 'all', constraints => $params, attachments => {projects => 1}};

  my $result = request('diffusion.repository.search', $data);

  if (exists $result->{result}{data} && @{$result->{result}{data}}) {
    return $class->new($result->{result}{data}[0]);
  }

  return undef;
}

sub is_uplift_repo {
  # Return a boolean indicating if this repository is an uplift repo.
  my ($self) = @_;

  foreach my $project (@{$self->projects}) {
    if ($project->name eq 'uplift') {
      return 1;
    }
  }

  return 0;
}

sub BUILDARGS {
  my ($class, $params) = @_;

  $params->{name}            = $params->{fields}->{name};
  $params->{description}     = $params->{fields}->{description}->{raw};
  $params->{vcs}             = $params->{fields}->{vcs};
  $params->{status}          = $params->{fields}->{status};
  $params->{call_sign}       = $params->{fields}->{callsign};
  $params->{short_name}      = $params->{fields}->{shortName};
  $params->{default_branch}  = $params->{fields}->{defaultBranch};
  $params->{creation_ts}     = $params->{fields}->{dateCreated};
  $params->{modification_ts} = $params->{fields}->{dateModified};
  $params->{view_policy}     = $params->{fields}->{policy}->{view};
  $params->{edit_policy}     = $params->{fields}->{policy}->{edit};
  $params->{push_policy}     = $params->{fields}->{policy}->{'diffusion.push'};
  $params->{projects_raw}    = $params->{attachments}->{projects};

  delete $params->{attachments};
  delete $params->{fields};

  return $params;
}

# {
#   "data": [
#     {
#       "id": 16,
#       "type": "REPO",
#       "phid": "PHID-REPO-kiqorvpaq7yy6mybuvz4",
#       "fields": {
#         "name": "ci-configuration",
#         "vcs": "hg",
#         "callsign": "CICONFIG",
#         "shortName": "ci-configuration",
#         "status": "active",
#         "isImporting": false,
#         "almanacServicePHID": null,
#         "refRules": {
#           "fetchRules": [],
#           "trackRules": [],
#           "permanentRefRules": []
#         },
#         "defaultBranch": "default",
#         "description": {
#           "raw": "Configuration for CI automation relating to the Gecko source code."
#         },
#         "spacePHID": null,
#         "dateCreated": 1523456273,
#         "dateModified": 1549657483,
#         "policy": {
#           "view": "public",
#           "edit": "admin",
#           "diffusion.push": "no-one"
#         }
#       },
#       "attachments": {
#         "projectsPHIDs": [
#           "PHID-PROJ-pioonhc34mzisujjvyvd"
#         ]
#       }
#     }
#   ],
#   "maps": {},
#   "query": {
#     "queryKey": null
#   },
#   "cursor": {
#     "limit": 100,
#     "after": null,
#     "before": null,
#     "order": null
#   }
# }

############
# Builders #
############

sub _build_projects {
  my ($self) = @_;

  return $self->{projects} if $self->{projects};
  return [] unless $self->projects_raw->{projectPHIDs};

  my @projects;
  foreach my $phid (@{$self->projects_raw->{projectPHIDs}}) {
    push @projects,
      Bugzilla::Extension::PhabBugz::Project->new_from_query({phids => [$phid]});
  }

  return $self->{projects} = \@projects;
}

1;
