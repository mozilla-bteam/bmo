package Bugzilla::PatchReader::Base;

use 5.10.1;
use strict;
use warnings;

sub new {
  my $class = shift;
  $class = ref($class) || $class;
  my $this = {};
  bless $this, $class;

  return $this;
}

sub sends_data_to {
  my $this = shift;
  if (defined($_[0])) {
    $this->{TARGET} = $_[0];
  }
  else {
    return $this->{TARGET};
  }
}

1
