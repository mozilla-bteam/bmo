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
use Getopt::Long            qw(GetOptions);

my @storage_names = Bugzilla::Attachment->get_storage_names();

my %options;
GetOptions(
  \%options,    'migrate=s@{2}', 'class=s@{2}', 'mirror=s@{2}',
  'copy=s@{2}', 'delete=s'
) or exit 1;
unless ($options{migrate}
  || $options{class}
  || $options{mirror}
  || $options{copy}
  || $options{delete})
{
  die <<EOF;
Syntax:
    migrate-attachments.pl --migrate source destination
    migrate-attachments.pl --class source destination
    migrate-attachments.pl --mirror source destination
    migrate-attachments.pl --copy source destination
    migrate-attachments.pl --delete source

'migrate'
    Migrates all attachments from the specified source to the destination.
    Attachments which already exist at the destination will be overwritten.
    This also sets the storage class so that the system loads the data from the
    new destination.

    e.g. migrate-attachments.pl --migrate database s3

'class'
    Only update the class value stored in the attachment_storage_class
    from the source value to the destination value. This is useful for
    when the data has been migrated using other means and you want the
    data to be loaded from the new location instead of the old.

    e.g. migrate-attachments.pl --class s3 google

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

if ($options{migrate}) {
  if ($options{migrate}->[0] eq $options{migrate}->[1]) {
    die "Source and destination must be different\n";
  }
  my ($source, $dest) = @{$options{migrate}};

  # Do not migrate from database to net storage if data is less than minsize
  my $where = '';
  if ( $source eq 'database'
    && $dest eq 's3'
    && Bugzilla->params->{attachment_s3_minsize})
  {
    $where .= ' AND attachments.attach_size > '
      . int Bugzilla->params->{attachment_s3_minsize};
  }
  elsif ($source eq 'database'
    && $dest eq 'google'
    && Bugzilla->params->{attachment_google_minsize})
  {
    $where .= ' AND attachments.attach_size > '
      . int Bugzilla->params->{attachment_google_minsize};
  }

  my ($total) = $dbh->selectrow_array('
    SELECT COUNT(*) 
      FROM attachments 
           JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
     WHERE attachment_storage_class.storage_class = ? ' . $where, undef, $source);

  confirm(sprintf 'Migrate %s attachments from %s to %s?',
    $total, @{$options{migrate}});

  my $sth = $dbh->prepare('
      SELECT attach_id 
        FROM attachments 
             JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
       WHERE attachment_storage_class.storage_class = ? ' . $where
      . ' ORDER BY attach_id DESC');
  $sth->execute($source);
  my ($count, $migrated) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({id => $attach_id, cached => 1});

    # skip deleted attachments
    next if $attachment->datasize == 0;

    # migrate the attachment
    if (my $data = $attachment->current_storage($source)->get_data()) {
      $attachment->current_storage($dest)->set_data($data)->set_class();
      $attachment->current_storage($source)->remove_data();
      $migrated++;
    }
  }
  print "\n";
  print "Attachments migrated: $migrated\n";
}

if ($options{class}) {
  if ($options{class}->[0] eq $options{class}->[1]) {
    die "Source and destination must be different\n";
  }
  my ($source, $dest) = @{$options{class}};

  my ($total) = $dbh->selectrow_array('
    SELECT COUNT(*) 
      FROM attachments 
           JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
     WHERE attachment_storage_class.storage_class = ?', undef, $source);

  confirm(sprintf 'Update %d attachments class from %s to %s?',
    $total, @{$options{class}});

  my $sth = $dbh->prepare('
      SELECT attach_id 
        FROM attachments 
             JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
       WHERE attachment_storage_class.storage_class = ? ORDER BY attach_id DESC');
  $sth->execute($source);
  my ($count, $updated) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({id => $attach_id, cached => 1});

    # Update the class of the attachment
    $attachment->current_storage($dest)->set_class();

    $updated++;
  }
  print "\n";
  print "Attachments updated: $updated\n";
}

if ($options{mirror}) {
  if ($options{mirror}->[0] eq $options{mirror}->[1]) {
    die "Source and destination must be different\n";
  }
  my ($source, $dest) = @{$options{mirror}};

  my ($total) = $dbh->selectrow_array('
    SELECT COUNT(*) 
      FROM attachments 
           JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
     WHERE attachment_storage_class.storage_class = ?', undef, $source);

  confirm(sprintf 'Mirror %s attachments from %s to %s?',
    $total, @{$options{mirror}});

  my $sth = $dbh->prepare('
      SELECT attach_id 
        FROM attachments 
             JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
       WHERE attachment_storage_class.storage_class = ? ORDER BY attach_id DESC');
  $sth->execute($source);
  my ($count, $deleted, $stored) = (0, 0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({id => $attach_id, cached => 1});

    # remove deleted attachments
    if ( $attachment->datasize == 0
      && $attachment->current_storage($dest)->data_exists())
    {
      $attachment->current_storage($dest)->remove_data();
      $deleted++;
    }

    # store attachments that don't already exist
    elsif ($attachment->datasize != 0
      && !$attachment->current_storage($dest)->data_exists())
    {
      if (my $data = $attachment->current_storage($source)->get_data()) {
        $attachment->current_storage($dest)->set_data($data);
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
  my ($source, $dest) = @{$options{copy}};

  my ($total) = $dbh->selectrow_array('
    SELECT COUNT(*) 
      FROM attachments 
           JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
     WHERE attachment_storage_class.storage_class = ?', undef, $source);

  confirm(sprintf 'Copy %s attachments from %s to %s?', $total,
    @{$options{copy}});

  my $sth = $dbh->prepare('
      SELECT attach_id 
        FROM attachments 
             JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
       WHERE attachment_storage_class.storage_class = ? ORDER BY attach_id DESC');
  $sth->execute($source);
  my ($count, $stored) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({id => $attach_id, cached => 1});

    # store attachments that don't already exist
    if (!$attachment->current_storage($dest)->data_exists()) {
      if (my $data = $attachment->current_storage($source)->get_data()) {
        $attachment->current_storage($dest)->set_data($data);
        $stored++;
      }
    }
  }
  print "\n";
  print "Attachments stored: $stored\n";
}

elsif ($options{delete}) {
  my $source = $options{delete};

  my ($total) = $dbh->selectrow_array('
    SELECT COUNT(*) 
      FROM attachments 
           JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
     WHERE attachment_storage_class.storage_class = ? AND attachments.attach_size != 0',
    undef, $source);

  confirm(sprintf 'DELETE %s attachments from %s?', $total, $options{delete});

  my $sth = $dbh->prepare('
      SELECT attach_id 
        FROM attachments 
             JOIN attachment_storage_class ON attachments.attach_id = attachment_storage_class.id 
       WHERE attachment_storage_class.storage_class = ? AND attachments.attach_size != 0 ORDER BY attach_id DESC'
  );
  $sth->execute($source);
  my ($count, $deleted) = (0, 0);
  while (my ($attach_id) = $sth->fetchrow_array()) {
    indicate_progress({total => $total, current => ++$count});

    my $attachment = Bugzilla::Attachment->new({id => $attach_id, cached => 1});

    if ($attachment->current_storage($source)->data_exists()) {
      $attachment->current_storage($source)->remove_data();
      $deleted++;
    }
  }
  print "\n";
  print "Attachments deleted: $deleted\n";
}

sub confirm {
  my ($prompt) = @_;
  print $prompt, "\n\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
  getc;
}
