#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
use Test::More;

my $ok = eval { require Test::Perl::Critic::Progressive };
plan skip_all => 'T::P::C::Progressive required for this test' unless $ok;

Test::Perl::Critic::Progressive::progressive_critic_ok();