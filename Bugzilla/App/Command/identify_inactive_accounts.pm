# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Command::identify_inactive_accounts;   ## no critic (Capitalization)
use Mojo::Base 'Mojolicious::Command';

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Report::InactiveUser;

use Mojo::Util 'getopt';

has description => 'identify inactive bugzilla accounts';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
  # getopt \@args,
  #   'option|o=s'    => \$option,
  #   'required|r=s'  => \$required;
  # die $self->usage unless $required;

  # Outputs a list of bugmails one per line
  # The part that does the query should be extractable, i.e. Bugzilla::Report::InactiveUser
  # Sort of like risk report thing, as a $report->users
  # Which domains to ignore -- very few, maybe just a regex?
  my $report = Bugzilla::Report::InactiveUser->new(dbh => Bugzilla->dbh);

  foreach my $user (@{ $report->userids }) {
      # Printing the list out for now
      say $user->email;
  }
}

1;

__END__

=head1 NAME

Bugzilla::App::Command::identify_inactive_accounts - identify inactive bugzilla accounts

=head1 SYNOPSIS

  Usage: APPLICATION identify_inactive_accounts

    ./bugzilla.pl identify_inactive_accounts

  Options:
    -h, --help               Print a brief help message and exits.

=head1 DESCRIPTION

This command finds all bugzilla accounts that are considered inactive and prints them to the screen.

=head1 ATTRIBUTES

L<Bugzilla::App::Command::identify_inactive_accounts> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $identify_inactive_accounts->description;
  $identify_inactive_accounts        = $identify_inactive_accounts->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $identify_inactive_accounts->usage;
  $identify_inactive_accounts  = $identify_inactive_accounts->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Bugzilla::App::Command::identify_inactive_accounts> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $identify_inactive_accounts->run(@ARGV);

Run this command.
