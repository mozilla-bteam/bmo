# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Test::MockParams;
use 5.10.1;
use strict;
use warnings;
use Try::Tiny;
use Capture::Tiny qw(capture_merged);
use Test2::Tools::Mock qw(mock);

use Bugzilla::Config;
use Bugzilla::Logging;

sub import {
  my ($self, %answers) = @_;

  require Bugzilla;
  my $Bugzilla = mock 'Bugzilla' =>
    (override => [installation_answers => sub { \%answers },],);

  # prod-like defaults
  $answers{user_info_class}   //= 'GitHubAuth,OAuth2,CGI';
  $answers{user_verify_class} //= 'GitHubAuth,DB';

  my $params = Bugzilla::Config->new;
  $params->set_param($_, $answers{$_}) for keys %answers;
  $params->update();
}

1;
