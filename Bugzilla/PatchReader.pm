package Bugzilla::PatchReader;

use 5.10.1;
use strict;
use warnings;

=head1 NAME

PatchReader - Utilities to read and manipulate patches and CVS

=head1 SYNOPSIS

  # Script that reads in a patch (in any known format), and prints
  # out some information about it.  Other common operations are
  # outputting the patch in a raw unified diff format, outputting
  # the patch information to Template::Toolkit templates, adding
  # context to a patch from CVS, and narrowing the patch down to
  # apply only to a single file or set of files.

  use PatchReader::Raw;
  use PatchReader::PatchInfoGrabber;
  my $filename = 'filename.patch';

  # Create the reader that parses the patch and the object that
  # extracts info from the reader's datastream
  my $reader = new PatchReader::Raw();
  my $patch_info_grabber = new PatchReader::PatchInfoGrabber();
  $reader->sends_data_to($patch_info_grabber);

  # Iterate over the file
  $reader->iterate_file($filename);

  # Print the output
  my $patch_info = $patch_info_grabber->patch_info();
  print "Summary of Changed Files:\n";
  while (my ($file, $info) = each %{$patch_info->{files}}) {
    print "$file: +$info->{plus_lines} -$info->{minus_lines}\n";
  }

=head1 ABSTRACT

This perl library allows you to manipulate patches programmatically by
chaining together a variety of objects that read, manipulate, and output
patch information:

=over

=item PatchReader::Raw

Parse a patch in any format known to this author (unified, normal, cvs diff,
among others)

=item PatchReader::PatchInfoGrabber

Grab summary info for sections of a patch in a nice hash

=item PatchReader::AddCVSContext

Add context to the patch by grabbing the original files from CVS

=item PatchReader::NarrowPatch

Narrow a patch down to only apply to a specific set of files

=item PatchReader::DiffPrinter::raw

Output the parsed patch in raw unified diff format

=item PatchReader::DiffPrinter::template

Output the parsed patch to L<Template::Toolkit> templates (can be used to make
HTML output or anything else you please)

=back

Additionally, it is designed so that you can plug in your own objects that
read the parsed data while it is being parsed (no need for the performance or
memory problems that can come from reading in the entire patch all at once).
You can do this by mimicking one of the existing readers (such as
PatchInfoGrabber) and overriding the methods start_patch, start_file, section,
end_file and end_patch.

=head1 AUTHORS

 John Keiser <jkeiser@cpan.org>
 Teemu Mannermaa <tmannerm@cpan.org>

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2003-2004, John Keiser and
 Copyright (C) 2011-2012, Teemu Mannermaa.

This module is free software; you can redistribute it and/or modify it under
the terms of the Artistic License 1.0. For details, see the full text of the
license at
 <http://www.perlfoundation.org/artistic_license_1_0>.

This module is distributed in the hope that it will be useful, but it is
provided "as is" and without any warranty; without even the implied warranty
of merchantability or fitness for a particular purpose.

Files with different licenses or copyright holders:

=over 

=item F<lib/PatchReader/CVSClient.pm>

Portions created by Netscape are
Copyright (C) 2003, Netscape Communications Corporation. All rights reserved.

This file is subject to the terms of the Mozilla Public License, v. 2.0.

=back

=cut

$Bugzilla::PatchReader::VERSION = '0.9.7';

1
