package Bugzilla::Extension::SecureMail::Params;

use strict;
use warnings;
use 5.10.1;

use Bugzilla::Config::Common;

sub get_param_list {
    my ($class) = @_;

    return (
        {
            name    => 'gpg_base_dir',
            desc    => 'Ephemeral directory which will hold user gpg keys',
            type    => 't',
            default => '/tmp',
        },
        {
            name    => 'gpg_cmd',
            desc    => 'The full path to the GPG command',
            type    => 't',
            default => '/usr/bin/gpg2',
        },
    );
}

1;

__END__

=head1 Description

Bugzilla::Extension::SecureMail::Params - A module for specifying parameters to be added to the data/params.json file.

=head1 Parameters

=over 4

=item gpg_base_dir

The path to the directory to be used for storing PGP public keys.

=item gpg_cmd

The full path to the GPG command

=item mail_delivery_override

The mail delivery method to use if the default mail method is Test and the User has override_test
enabled. If this is unset then users will not be able to override the Test method.

=back

