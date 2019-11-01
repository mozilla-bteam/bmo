#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
$| = 1;


use Bugzilla;
use Bugzilla::Attachment;
use Bugzilla::Install::Util qw(indicate_progress);
use Getopt::Long qw(GetOptions);

my @storage_names = Bugzilla::Attachment->get_storage_names();

my %options;
GetOptions(\%options, 'mirror=s@{2}', 'copy=s@{2}', 'delete=s') or exit(1);
unless ($options{mirror} || $options{copy} || $options{delete}) {
  die <<EOF;
Syntax:
    migrate-attachments.pl --mirror source destination
    migrate-attachments.pl --copy source destination
    migrate-attachments.pl --delete source

'mirror'
    Copies all attachments from the specified source to the destination.
    Attachments which already exist at the destination will not be copied
    again. Attachments deleted on the source will be deleted from the
    destination.

    e.g. migrate-attachments.pl --mirror database s3

'copy'
    Copies all attachments from the specified source to the destination.
    Attachments which already exist at the destination will not be copied
    again. Unlike 'mirror', attachments deleted from the source will not be
    removed from the destination.

    e.g. migrate-attachments.pl --copy database s3

'delete'
    Deletes all attachments in the specified location.  This operation cannot
    be undone.

    e.g. migrate-attachments.pl --delete database

Valid locations:
    @storage_names

EOF
}

my $dbh = Bugzilla->dbh;

if ($options{mirror}) {
  if ($options{mirror}->[0] eq $options{mirror}->[1]) {
    die "Source and destination must be different\n";
  }
  my ($source, $dest) = map { storage($_) } @{$options{mirror}};

  my ($total) = $dbh->selectrow_array("SELECT COUNT(*) FROM attachments");
  confirm(sprintf(
    'Mirror %s attachments from %s to %s?', $total, @{$options{mirror}}));

  my $sth = $dbh->prepare(
    "SELECT attach_id FROM attachments ORDER BY attach_id DESC");
  $sth->execute();
  my ($count, $deleted, $stored) = (0, 0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({ id => $attach_id, cached => 1 });

    # remove deleted attachments
    if ($attachment->size == 0 && $dest->exists($attachment)) {
      $dest->remove($attachment);
      $deleted++;
    }

    # store attachments that don't already exist
    elsif ($attachment->size != 0 && !$dest->exists($attachment)) {
      if (my $data = $source->retrieve($attachment)) {
        $dest->store($attachment, $data);
        $stored++;
      }
    }
  }
  print "\n";
  print "Attachments stored: $stored\n";
  print "Attachments deleted: $deleted\n" if $deleted;
}

elsif ($options{copy}) {
  if ($options{copy}->[0] eq $options{copy}->[1]) {
    die "Source and destination must be different\n";
  }
  my ($source, $dest) = map { storage($_) } @{$options{copy}};

  my ($total)
    = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM attachments WHERE attach_size != 0");
  confirm(sprintf(
    'Copy %s attachments from %s to %s?', $total, @{$options{copy}}));

  my $sth
    = $dbh->prepare(
    "SELECT attach_id FROM attachments WHERE attach_size != 0 ORDER BY attach_id DESC"
    );
  $sth->execute();
  my ($count, $stored) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({ id => $attach_id, cached => 1 });

    # store attachments that don't already exist
    if (!$dest->exists($attachment)) {
      if (my $data = $source->retrieve($attachment)) {
        $dest->store($attachment, $data);
        $stored++;
      }
    }
  }
  print "\n";
  print "Attachments stored: $stored\n";
}

elsif ($options{delete}) {
  my $storage = storage($options{delete});
  my ($total)
    = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM attachments WHERE attach_size != 0");
  confirm(sprintf('DELETE %s attachments from %s?', $total, $options{delete}));

  my $sth
    = $dbh->prepare(
    "SELECT attach_id FROM attachments WHERE attach_size != 0 ORDER BY attach_id DESC"
    );
  $sth->execute();
  my ($count, $deleted) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({ id => $attach_id, cached => 1 });

    if ($storage->exists($attachment)) {
      $storage->remove($attachment);
      $deleted++;
    }
  }
  print "\n";
  print "Attachments deleted: $deleted\n";
}

sub storage {
  my ($name) = @_;
  my $storage = Bugzilla::Attachment::get_storage_by_name($name)
    or die "Invalid attachment location: $name\n";
  return $storage;
}

sub confirm {
  my ($prompt) = @_;
  print $prompt, "\n\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
  getc();
}
