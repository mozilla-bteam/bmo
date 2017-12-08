# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Archive;

use 5.10.1;
use Moo;
use Digest::SHA qw(sha256);
use Carp;
use IO::File;

use constant HEADER_SIZE   => 45;
use constant HEADER_FORMAT => 'ANNNA32';

has 'file'      => ( is => 'ro',   required  => 1 );
has 'input_fh'  => ( is => 'lazy', predicate => 'has_input_fh' );
has 'output_fh' => ( is => 'lazy', predicate => 'has_output_fh' );
has 'checksum'  => ( is => 'lazy', clearer   => 'reset_checksum' );

sub read_member {
    my ($self) = @_;
    my $header = $self->_read_header();
    my ($type, $bug_id, $attach_id, $data_len, $hash) = unpack HEADER_FORMAT, $header;
    if ( $type eq 'D' ) {
        $self->checksum->add($header);
        my $data = $self->_read_data( $data_len, $hash );
        return {
            bug_id    => $bug_id,
            attach_id => $attach_id,
            data_len  => $data_len,
            hash      => $hash,
            data      => $data,
        };
    }
    elsif ($type eq 'C') {
        die "bad overall checksum\n" unless $hash eq $self->checksum->digest;
        $self->reset_checksum;
        return undef;
    }
    else {
        die "unknown member type: $type\n";
    }
}

sub write_attachment {
    my ( $self, $attachment ) = @_;
    my $data      = $attachment->data;
    my $bug_id    = $attachment->bug_id;
    my $attach_id = $attachment->id;
    my $header    = pack HEADER_FORMAT, 'D', $bug_id, $attach_id, length($data), sha256($data);

    $self->checksum->add($header);
    $self->output_fh->print($header, $data);
}

sub write_checksum {
    my ($self) = @_;
    my $header = pack HEADER_FORMAT, 'C', 0, 0, 0, $self->checksum->digest;
    $self->output_fh->print($header);
    $self->reset_checksum;
}

sub _build_checksum {
    my ($self) = @_;
    return Digest::SHA->new(256);
}

sub _build_input_fh {
    my ($self) = @_;
    if ($self->has_output_fh) {
        croak "I will not read and write a file at the same time";
    }
    return IO::File->new($self->file, '<:bytes');
}

sub _build_output_fh {
    my ($self) = @_;
    if ($self->has_input_fh) {
        croak "I will not read and write a file at the same time";
    }
    if (-e $self->file) {
        my $f = $self->file;
        croak "I will not overwrite a file (file $f already exists)";
    }
    return IO::File->new($self->file, '>:bytes');
}

sub _read_header {
    my ($self) = @_;
    my $header     = '' x HEADER_SIZE;
    my $header_len = $self->input_fh->read($header, HEADER_SIZE);
    if ( !$header_len || $header_len != HEADER_SIZE ) {
        die "bad header\n";
    }
    return $header;
}

sub _read_data {
    my ($self, $data_len, $hash) = @_;

    my $data = '' x $data_len;
    my $read_data_len = $self->input_fh->read($data, $data_len);

    unless ( $hash eq sha256($data) ) {
        die "bad checksum\n";
    }

    unless ( $read_data_len == $data_len ) {
        die "bad data\n";
    }

    return $data;
}

1;