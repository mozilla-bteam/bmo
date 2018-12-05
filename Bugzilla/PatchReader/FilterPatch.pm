package Bugzilla::PatchReader::FilterPatch;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::PatchReader::Base;

@Bugzilla::PatchReader::FilterPatch::ISA = qw(Bugzilla::PatchReader::Base);

sub new {
  my $class = shift;
  $class = ref($class) || $class;
  my $this = $class->SUPER::new();
  bless $this, $class;

  return $this;
}

sub start_patch {
  my $this = shift;
  $this->{TARGET}->start_patch(@_) if $this->{TARGET};
}

sub end_patch {
  my $this = shift;
  $this->{TARGET}->end_patch(@_) if $this->{TARGET};
}

sub start_file {
  my $this = shift;
  $this->{TARGET}->start_file(@_) if $this->{TARGET};
}

sub end_file {
  my $this = shift;
  $this->{TARGET}->end_file(@_) if $this->{TARGET};
}

sub next_section {
  my $this = shift;
  $this->{TARGET}->next_section(@_) if $this->{TARGET};
}

1
