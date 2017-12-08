#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;

use File::Basename;
use File::Spec;

BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs( File::Spec->catdir( dirname(__FILE__), '..' ) );
    lib->import( $dir, File::Spec->catdir( $dir, 'lib' ), File::Spec->catdir( $dir, qw(local lib perl5) ) );
}

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Attachment;
use Digest::SHA qw(sha256);
use Getopt::Long;
use Pod::Usage;

BEGIN { Bugzilla->extensions }

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $help;
GetOptions("help|h" => \$help);
pod2usage(1) if $help || -t STDOUT;

binmode STDOUT, ':bytes';

while ( my $attach_id = <> ) {
    chomp $attach_id;
    my $attachment = Bugzilla::Attachment->new($attach_id);
    unless ($attachment) {
        warn "No attachment: $attachment\n";
        next;
    }
    my $data   = $attachment->data;
    my $hash   = sha256($data);
    my $bug_id = $attachment->bug_id;
    print pack 'NNNa32a*', $bug_id, $attach_id, length($data), sha256($data), $data;
}

__DATA__

=head1 NAME

archive-attachments.pl - save attachments to a dump file

=head1 SYNOPSIS

    ./scripts/archive-attachments.pl < list-of-attachment-ids.txt > attachments-dump-file

=head1 SEE ALSO

L<./scripts/restore-attachments.pl>