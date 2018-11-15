package Perl::Critic::Policy::BMO::MissingImports;
use strict;
use warnings;

use Perl::Critic::Utils qw{ :severities :classification :ppi };
use base qw(Perl::Critic::Policy);
use Carp;

my $DESCRIPTION = q{Need to explicitely load %s};
my $EXPLANATION = "It looks like a class method was called without loading the class in the current file.";

sub default_severity { $SEVERITY_LOW }
sub default_themes   { 'bugs' }
sub applies_to       { 'PPI::Statement::Include', 'PPI::Token::Word' }

sub initialize_if_enabled {
    my ($self, $config) = @_;
    $self->{__imported} = { Bugzilla => 1 };
    return $self->SUPER::initialize_if_enabled($config);
}

sub violates {
  my ($self, $node, undef) = @_;

  if ($node->isa('PPI::Statement::Include')) {
      if ($node->module) {
          $self->{__imported}{ $node->module }++;
      }
  }
  else {
      if (is_class_name($node) && ! $self->{__imported}{ $node->literal }) {
          return $self->violation(sprintf($DESCRIPTION, $node->literal), $EXPLANATION, $node);
      }
  }
  return;
}

1;
