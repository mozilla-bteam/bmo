# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::SearchAPI::Util;

use 5.10.1;
use strict;
use warnings;

use SQL::Tokenizer;

use base qw(Exporter);

our @EXPORT_OK = qw(named_params);

use constant NAMED_PREFIX => ':';
use constant NAMED_SUFFIX => ':';

# Same workflow borrowed from
# https://metacpan.org/pod/DBIx::Placeholder::Named
sub named_params {
  my ($query, $params) = @_;

  # Convert SQL statement in series of tokens
  my @query_tokens = SQL::Tokenizer->tokenize($query);

  my $prefix_length = length NAMED_PREFIX;
  my $suffix_length = length NAMED_SUFFIX;

  my @values;
  foreach my $token (@query_tokens) {
    if (substr($token, 0, $prefix_length) eq NAMED_PREFIX) {
      my $multiple_values = 0;

      # Remove NAMED_PREFIX from beginning
      my $token_stripped = substr $token, $prefix_length;

      # Check to see if placeholder specifies list of values (ends with NAMED_SUFFIX)
      my $token_length = length $token_stripped;
      if (
        substr($token_stripped, $token_length - $suffix_length, $suffix_length) eq
        NAMED_SUFFIX)
      {

        # Remove the NAMED_SUFFIX from the end of the stripped token
        $token_stripped  = substr $token_stripped, 0, $token_length - $suffix_length;
        $multiple_values = 1;
      }

      # Look for passed parameter and value(s) for the placeholder detected
      if (defined $params->{$token_stripped}) {
        if ($multiple_values && ref $params->{$token_stripped} ne 'ARRAY') {
          return (undef,
            "Parameter $token_stripped not found for $token or not an array");
        }
        push @values,
          (
          $multiple_values ? @{$params->{$token_stripped}} : $params->{$token_stripped});
      }
      else {
        # No need to proceed if parameter value is missing
        return (undef, "Parameter $token_stripped not found for $token");
      }

      # Replace current token position with correct number of placeholders
      if ($multiple_values) {
        $token = join ',', map {'?'} @{$params->{$token_stripped}};
      }
      else {
        $token = '?';
      }
    }
  }

  # Create new SQL stratement from tokens
  my $new_query = join '', @query_tokens;

  return ($new_query, \@values);
}

1;
