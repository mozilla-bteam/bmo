# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Comment;

use 5.10.1;
use Moo;
use Types::Standard -all;

use Bugzilla::Extension::PhabBugz::User;
use Bugzilla::Extension::PhabBugz::Types qw(:types);

#########################
#    Initialization     #
#########################

has id              => (is => 'ro',   isa => Int);
has phid            => (is => 'ro',   isa => Str);
has author_phid     => (is => 'ro',   isa => Str);
has creation_ts     => (is => 'ro',   isa => Str);
has modification_ts => (is => 'ro',   isa => Str);
has text            => (is => 'ro',   isa => Str);
has author          => (is => 'lazy', isa => PhabUser);

sub BUILDARGS {
  my ($class, $params) = @_;

  $params->{author_phid}     = $params->{authorPHID};
  $params->{creation_ts}     = $params->{dateCreated};
  $params->{modification_ts} = $params->{dateModified};
  $params->{text}            = $params->{content}{raw};

  return $params;
}

# {
#   "id": 1424261,
#   "phid": "PHID-XCMT-thonchbcyvvwkcjq2bwa",
#   "version": 1,
#   "authorPHID": "PHID-APPS-PhabricatorHeraldApplication",
#   "dateCreated": 1754346670,
#   "dateModified": 1754346670,
#   "removed": false,
#   "content": {
#     "raw": "This revision requires a [[https://firefox-source-docs.mozilla.org/testing/testing-policy/ | Testing Policy]] Project Tag to be set before landing. Please apply one of `testing-approved`, `testing-exception-unchanged`, `testing-exception-ui`, `testing-exception-elsewhere`, `testing-exception-other`. Tip: [[https://addons.mozilla.org/en-US/firefox/addon/phab-test-policy/ | this Firefox add-on]] makes it easy!"
#   }
# }

############
# Builders #
############

sub _build_author {
  my ($self) = @_;
  return $self->{author} if $self->{author};
  my $phab_user
    = Bugzilla::Extension::PhabBugz::User->new_from_query({
    phids => [$self->author_phid]
    });
  return $self->{author} = $phab_user;
}

1;
