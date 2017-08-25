# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Bloomfilter;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Algorithm::BloomFilter;
use File::Temp qw(tempfile);

sub _new_bloom_filter {
    my ($n) = @_;
    my $p = 0.01;
    my $m = $n * abs(log $p) / log(2) ** 2;
    my $k = $m / $n * log(2);
    return Algorithm::BloomFilter->new($m, $k);
}

sub _filename {
    my ($name) = @_;

    my $datadir = bz_locations->{datadir};
    return sprintf("%s/%s.bloom", $datadir, $name);
}

sub populate {
    my ($class, $name, $items) = @_;

    my $filter = _new_bloom_filter(@$items + 0);
    foreach my $item (@$items) {
        $filter->add($item);
    }

    my ($fh, $filename) = tempfile( "${name}XXXXXX", DIR => bz_locations->{datadir}, UNLINK => 0);
    binmode $fh, ':bytes';
    print $fh $filter->serialize;
    close $fh;
    rename($filename, _filename($name)) or die "failed to rename $filename: $!";
}

sub load {
    my ($class, $name) = @_;

    my $filename = _filename($name);

    if (-f $filename) {
        open my $fh, '<:bytes', $filename;
        local $/ = undef;
        my $s = <$fh>;
        close $fh;

        my $filter = Algorithm::BloomFilter->deserialize($s);
        return $filter;
    }
    else {
        return Algorithm::BloomFilter->new(8, 2);
    }
}

1;
