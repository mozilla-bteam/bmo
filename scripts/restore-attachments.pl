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
use Digest::SHA qw(sha256 sha256_hex);

BEGIN { Bugzilla->extensions }

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

binmode STDIN, ':bytes';

while ( my ( $bug_id, $attach_id, $data_len, $hash ) = read_header()) {
    warn "bug $bug_id, attachment $attach_id, size $data_len.\n";
    my $data = read_data($data_len, $hash);

    my $attachment = Bugzilla::Attachment->new($attach_id);
    next unless check_attachment($attachment, $bug_id, $data_len);

    Bugzilla::Attachment::current_storage()->store( $attachment->id, $data );
}

sub check_attachment {
    my ($attachment, $bug_id, $data_len) = @_;

    unless ($attachment) {
        warn "No attachment found. Skipping record.\n";
        next;
    }
    unless ( $attachment->bug_id == $bug_id ) {
        warn 'Wrong bug id (should be ' . $attachment->bug_id . ")\n";
        return 0;
    }
    unless ( $attachment->datasize == $data_len ) {
        warn 'Wrong size (should be ' . $attachment->datasize . ")\n";
        return 0;
    }

    return 1;
}

# Keeping this close to the code that depends on it.
use constant HEADER_SIZE => 44;

sub read_header {
    my $header     = '' x HEADER_SIZE;
    my $header_len = read STDIN, $header, HEADER_SIZE;
    if ( !$header_len || $header_len != HEADER_SIZE ) {
        die "bad header\n";
    }
    return unpack 'NNNa32', $header;
}

sub read_data {
    my ($data_len, $hash) = @_;

    my $data = '' x $data_len;
    my $read_data_len = read STDIN, $data, $data_len;

    unless ( $hash eq sha256($data) ) {
        die "bad checksum\n";
    }

    unless ( $read_data_len == $data_len ) {
        die "bad data\n";
    }

    return $data;
}

