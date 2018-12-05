# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Search::Quicksearch;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Keyword;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::Util;

use List::Util qw(min max);
use List::MoreUtils qw(firstidx);
use Text::ParseWords qw(parse_line);

use base qw(Exporter);
@Bugzilla::Search::Quicksearch::EXPORT = qw(quicksearch);

# Custom mappings for some fields.
use constant MAPPINGS => {

  # Status, Resolution, Platform, OS, Priority, Severity
  "status"   => "bug_status",
  "platform" => "rep_platform",
  "os"       => "op_sys",
  "severity" => "bug_severity",

  # People: AssignedTo, Reporter, QA Contact, CC, etc.
  "assignee" => "assigned_to",
  "owner"    => "assigned_to",
  "mentor"   => "bug_mentor",

  # Product, Version, Component, Target Milestone
  "milestone" => "target_milestone",

  # Summary, Description, URL, Status whiteboard, Keywords
  "summary"     => "short_desc",
  "description" => "longdesc",
  "comment"     => "longdesc",
  "url"         => "bug_file_loc",
  "whiteboard"  => "status_whiteboard",
  "sw"          => "status_whiteboard",
  "kw"          => "keywords",
  "group"       => "bug_group",

  # Flags
  "flag"      => "flagtypes.name",
  "requestee" => "requestees.login_name",
  "setter"    => "setters.login_name",

  # Attachments
  "attachment"         => "attachments.description",
  "attachmentdesc"     => "attachments.description",
  "attachdesc"         => "attachments.description",
  "attachmentmimetype" => "attachments.mimetype",
  "attachmimetype"     => "attachments.mimetype"
};

sub FIELD_MAP {
  my $cache = Bugzilla->request_cache;
  return $cache->{quicksearch_fields} if $cache->{quicksearch_fields};

  # Get all the fields whose names don't contain periods. (Fields that
  # contain periods are always handled in MAPPINGS.)
  my @db_fields = grep { $_->name !~ /\./ } @{Bugzilla->fields({obsolete => 0})};
  my %full_map = (%{MAPPINGS()}, map { $_->name => $_->name } @db_fields);

  # Eliminate the fields that start with bug_ or rep_, because those are
  # handled by the MAPPINGS instead, and we don't want too many names
  # for them. (Also, otherwise "rep" doesn't match "reporter".)
  #
  # Remove "status_whiteboard" because we have "whiteboard" for it in
  # the mappings, and otherwise "stat" can't match "status".
  #
  # Also, don't allow searching the _accessible stuff via quicksearch
  # (both because it's unnecessary and because otherwise
  # "reporter_accessible" and "reporter" both match "rep".
  delete @full_map{
    qw(rep_platform bug_status bug_file_loc bug_group
      bug_severity bug_status
      status_whiteboard
      cclist_accessible reporter_accessible)
  };

  Bugzilla::Hook::process('quicksearch_map', {'map' => \%full_map});

  $cache->{quicksearch_fields} = \%full_map;

  return $cache->{quicksearch_fields};
}

# Certain fields, when specified like "field:value" get an operator other
# than "substring"
use constant FIELD_OPERATOR =>
  {content => 'matches', owner_idle_time => 'greaterthan',};

# Mappings for operators symbols to support operators other than "substring"
use constant OPERATOR_SYMBOLS => {
  ':'  => 'substring',
  '='  => 'equals',
  '!=' => 'notequals',
  '>=' => 'greaterthaneq',
  '<=' => 'lessthaneq',
  '>'  => 'greaterthan',
  '<'  => 'lessthan',
};

# We might want to put this into localconfig or somewhere
use constant PRODUCT_EXCEPTIONS => (
  'row',    # [Browser]
            #   ^^^
  'new',    # [MailNews]
            #      ^^^
);
use constant COMPONENT_EXCEPTIONS => (
  'hang'    # [Bugzilla: Component/Keyword Changes]
            #                               ^^^^
);

# Quicksearch-wide globals for boolean charts.
our ($chart, $and, $or, $fulltext, $bug_status_set, $ELASTIC);

sub quicksearch {
  my ($searchstring) = (@_);
  my $cgi = Bugzilla->cgi;

  $chart = 0;
  $and   = 0;
  $or    = 0;

  # Remove leading and trailing commas and whitespace.
  $searchstring =~ s/(^[\s,]+|[\s,]+$)//g;
  ThrowUserError('buglist_parameters_required') unless ($searchstring);

  if ($searchstring =~ m/^[0-9,\s]*$/) {
    _bug_numbers_only($searchstring);
  }
  else {
    _handle_alias($searchstring);

    # Retain backslashes and quotes, to know which strings are quoted,
    # and which ones are not.
    my @words = _parse_line('\s+', 1, $searchstring);

    # If parse_line() returns no data, this means strings are badly quoted.
    # Rather than trying to guess what the user wanted to do, we throw an error.
    scalar(@words) || ThrowUserError('quicksearch_unbalanced_quotes',
      {string => $searchstring, quicksearch => $searchstring});

    # A query cannot start with AND or OR, nor can it end with AND, OR or NOT.
    ThrowUserError('quicksearch_invalid_query', {quicksearch => $searchstring})
      if ($words[0] =~ /^(?:AND|OR)$/ || $words[$#words] =~ /^(?:AND|OR|NOT)$/);

    $fulltext = Bugzilla->user->setting('quicksearch_fulltext') eq 'on' ? 1 : 0;

    my (@qswords, @or_group);
    while (scalar @words) {
      my $word = shift @words;

      # AND is the default word separator, similar to a whitespace,
      # but |a AND OR b| is not a valid combination.
      if ($word eq 'AND') {
        ThrowUserError('quicksearch_invalid_query',
          {operators => ['AND', 'OR'], quicksearch => $searchstring})
          if $words[0] eq 'OR';
      }

      # |a OR AND b| is not a valid combination.
      # |a OR OR b| is equivalent to |a OR b| and so is harmless.
      elsif ($word eq 'OR') {
        ThrowUserError('quicksearch_invalid_query',
          {operators => ['OR', 'AND'], quicksearch => $searchstring})
          if $words[0] eq 'AND';
      }

      # NOT negates the following word.
      # |NOT AND| and |NOT OR| are not valid combinations.
      # |NOT NOT| is fine but has no effect as they cancel themselves.
      elsif ($word eq 'NOT') {
        $word = shift @words;
        next if $word eq 'NOT';
        if ($word eq 'AND' || $word eq 'OR') {
          ThrowUserError('quicksearch_invalid_query',
            {operators => ['NOT', $word], quicksearch => $searchstring});
        }
        unshift(@words, "-$word");
      }

      # --comment and ++comment disable or enable fulltext searching
      elsif ($word =~ /^(--|\+\+)comments?$/i) {
        $fulltext = $1 eq '--' ? 0 : 1;
      }
      else {
        # OR groups words together, as OR has higher precedence than AND.
        push(@or_group, $word);

        # If the next word is not OR, then we are not in a OR group,
        # or we are leaving it.
        if (!defined $words[0] || $words[0] ne 'OR') {
          push(@qswords, join('|', @or_group));
          @or_group = ();
        }
      }
    }

    _handle_status_and_resolution($qswords[0]);
    shift(@qswords) if $bug_status_set;

    my (@unknownFields, %ambiguous_fields);

    # Loop over all main-level QuickSearch words.
    foreach my $qsword (@qswords) {
      my @or_operand = _parse_line('\|', 1, $qsword);
      foreach my $term (@or_operand) {
        next unless defined $term;
        my $negate = substr($term, 0, 1) eq '-';
        if ($negate) {
          $term = substr($term, 1);
        }

        next if _handle_special_first_chars($term, $negate);
        next
          if _handle_field_names($term, $negate, \@unknownFields, \%ambiguous_fields);

        # Having ruled out the special cases, we may now split
        # by comma, which is another legal boolean OR indicator.
        # Remove quotes from quoted words, if any.
        @words = _parse_line(',', 0, $term);
        foreach my $word (@words) {
          if (!_special_field_syntax($word, $negate)) {
            _default_quicksearch_word($word, $negate);
          }
          _handle_urls($word, $negate);
        }
      }
      $chart++;
      $and = 0;
      $or  = 0;
    }

    # If there is no mention of a bug status, we restrict the query
    # to open bugs by default.
    unless ($bug_status_set) {
      $cgi->param('bug_status', BUG_STATE_OPEN);
    }

    # Inform user about any unknown fields
    if (scalar(@unknownFields) || scalar(keys %ambiguous_fields)) {
      ThrowUserError(
        "quicksearch_unknown_field",
        {
          unknown     => \@unknownFields,
          ambiguous   => \%ambiguous_fields,
          quicksearch => $searchstring
        }
      );
    }

    # Make sure we have some query terms left
    scalar($cgi->param()) > 0 || ThrowUserError("buglist_parameters_required");
  }

  # List of quicksearch-specific CGI parameters to get rid of.
  my @params_to_strip = ('quicksearch', 'load', 'run');
  my $modified_query_string = $cgi->canonicalise_query(@params_to_strip);

  if ($cgi->param('load')) {
    my $urlbase = Bugzilla->localconfig->{urlbase};

    # Param 'load' asks us to display the query in the advanced search form.
    print $cgi->redirect(
      -uri => "${urlbase}query.cgi?format=advanced&amp;" . $modified_query_string);
  }

  # Otherwise, pass the modified query string to the caller.
  # We modified $cgi->params, so the caller can choose to look at that, too,
  # and disregard the return value.
  $cgi->delete(@params_to_strip);
  return $modified_query_string;
}

##########################
# Parts of quicksearch() #
##########################

sub _parse_line {
  my ($delim, $keep, $line) = @_;
  return () unless defined $line;

  # parse_line always treats ' as a quote character, making it impossible
  # to sanely search for contractions. As this behavour isn't
  # configurable, we replace ' with a placeholder to hide it from the
  # parser.

  # only treat ' at the start or end of words as quotes
  # it's easier to do this in reverse with regexes
  $line =~ s/(^|\s|:)'/$1\001/g;
  $line =~ s/'($|\s)/\001$1/g;
  $line =~ s/\\?'/\000/g;
  $line =~ tr/\001/'/;

  my @words = parse_line($delim, $keep, $line);
  foreach my $word (@words) {
    $word =~ tr/\000/'/ if defined $word;
  }
  return @words;
}

sub _bug_numbers_only {
  my $searchstring = shift;
  my $cgi          = Bugzilla->cgi;

  # Allow separation by comma or whitespace.
  $searchstring =~ s/[,\s]+/,/g;

  if ($searchstring !~ /,/ && !i_am_webservice()) {

    # Single bug number; shortcut to show_bug.cgi.
    print $cgi->redirect(
      -uri => Bugzilla->localconfig->{urlbase} . "show_bug.cgi?id=$searchstring");
    exit;
  }
  else {
    # List of bug numbers.
    $cgi->param('bug_id',      $searchstring);
    $cgi->param('order',       'bugs.bug_id');
    $cgi->param('bug_id_type', 'anyexact');
  }
}

sub _handle_alias {
  my $searchstring = shift;
  if ($searchstring =~ /^([^,\s]+)$/) {
    my $alias = $1;

    # We use this direct SQL because we want quicksearch to be VERY fast.
    my $bug_id
      = Bugzilla->dbh->selectrow_array(q{SELECT bug_id FROM bugs WHERE alias = ?},
      undef, $alias);

    # If the user cannot see the bug or if we are using a webservice,
    # do not resolve its alias.
    if ($bug_id && Bugzilla->user->can_see_bug($bug_id) && !i_am_webservice()) {
      $alias = url_quote($alias);
      print Bugzilla->cgi->redirect(
        -uri => Bugzilla->localconfig->{urlbase} . "show_bug.cgi?id=$alias");
      exit;
    }
  }
}

sub _handle_status_and_resolution {
  my $word           = shift;
  my $legal_statuses = get_legal_field_values('bug_status');
  my (%states, %resolutions);
  $bug_status_set = 1;

  if ($word =~ s/^(ALL|OPEN)\+$/$1/) {
    Bugzilla->cgi->param('limit' => 0);
  }

  if ($word eq 'OPEN') {
    $states{$_} = 1 foreach BUG_STATE_OPEN;
  }

  # If we want all bugs, then there is nothing to do.
  elsif ($word ne 'ALL'
    && !matchPrefixes(\%states, \%resolutions, $word, $legal_statuses))
  {
    $bug_status_set = 0;
  }

  # If we have wanted resolutions, allow closed states
  if (keys(%resolutions)) {
    foreach my $status (@$legal_statuses) {
      $states{$status} = 1 unless is_open_state($status);
    }
  }

  Bugzilla->cgi->param('bug_status', keys(%states));
  Bugzilla->cgi->param('resolution', keys(%resolutions));
}


sub _handle_special_first_chars {
  my ($qsword, $negate) = @_;
  return 0 if !defined $qsword || length($qsword) <= 1;

  my $firstChar = substr($qsword, 0, 1);
  my $baseWord = substr($qsword, 1);
  my @subWords = split(/,/, $baseWord);

  if ($firstChar eq '#') {
    addChart('short_desc', 'substring', $baseWord, $negate);
    addChart('content', 'matches', _matches_phrase($baseWord), $negate)
      if $fulltext;
    return 1;
  }
  if ($firstChar eq ':') {
    foreach (@subWords) {
      addChart('product',   'substring', $_, $negate);
      addChart('component', 'substring', $_, $negate);
    }
    return 1;
  }
  if ($firstChar eq '@') {
    addChart('assigned_to', 'substring', $_, $negate) foreach (@subWords);
    return 1;
  }
  if ($firstChar eq '[') {
    addChart('short_desc',        'substring', $baseWord, $negate);
    addChart('status_whiteboard', 'substring', $baseWord, $negate);
    return 1;
  }
  if ($firstChar eq '!') {
    addChart('keywords', 'anywords', $baseWord, $negate);
    return 1;
  }
  return 0;
}

sub _handle_field_names {
  my ($or_operand, $negate, $unknownFields, $ambiguous_fields) = @_;

  # Flag and requestee shortcut
  if ($or_operand =~ /^(?:flag:)?([^\?]+\?)([^\?]*)$/) {

    # BMO: Do not treat custom fields as flags if value is ?
    if ($1 !~ /^cf_/) {
      my ($flagtype, $requestee) = ($1, $2);
      addChart('flagtypes.name', 'substring', $flagtype, $negate);
      if ($requestee) {

        # AND
        $chart++;
        $and = $or = 0;
        addChart('requestees.login_name', 'substring', $requestee, $negate);
      }
      return 1;
    }
  }

  # Generic field1,field2,field3:value1,value2 notation.
  # We have to correctly ignore commas and colons in quotes.
  # Longer operators must be tested first as we don't want single character
  # operators such as <, > and = to be tested before <=, >= and !=.
  my @operators = sort { length($b) <=> length($a) } keys %{OPERATOR_SYMBOLS()};

  foreach my $symbol (@operators) {
    my @field_values = _parse_line($symbol, 1, $or_operand);
    next unless scalar @field_values == 2;
    my @fields = _parse_line(',', 1, $field_values[0]);
    my @values = _parse_line(',', 1, $field_values[1]);
    foreach my $field (@fields) {
      my $translated = _translate_field_name($field);

      # Skip and record any unknown fields
      if (!defined $translated) {
        push(@$unknownFields, $field);
      }

      # If we got back an array, that means the substring is
      # ambiguous and could match more than field name
      elsif (ref $translated) {
        $ambiguous_fields->{$field} = $translated;
      }
      else {
        if ($translated eq 'bug_status' || $translated eq 'resolution') {
          $bug_status_set = 1;
        }
        foreach my $value (@values) {
          next unless defined $value;
          my $operator
            = FIELD_OPERATOR->{$translated} || OPERATOR_SYMBOLS->{$symbol} || 'substring';

          # If the string was quoted to protect some special
          # characters such as commas and colons, we need
          # to remove quotes.
          if ($value =~ /^(["'])(.+)\1$/) {
            $value = $2;
            $value =~ s/\\(["'])/$1/g;
          }

          # If the value is a pair of matching quotes, the person wanted the empty string
          elsif ($value =~ /^(["'])\1$/ || $translated eq 'resolution' && $value eq '---')
          {
            $value    = "";
            $operator = "isempty";
          }
          addChart($translated, $operator, $value, $negate);
        }
      }
    }
    return 1;
  }
  return 0;
}

sub _translate_field_name {
  my $field = shift;
  $field = lc($field);
  my $field_map = FIELD_MAP;

  # If the field exactly matches a mapping, just return right now.
  return $field_map->{$field} if exists $field_map->{$field};

  # Check if we match, as a starting substring, exactly one field.
  my @field_names = keys %$field_map;
  my @matches = grep { $_ =~ /^\Q$field\E/ } @field_names;

  # Eliminate duplicates that are actually the same field
  # (otherwise "assi" matches both "assignee" and "assigned_to", and
  # the lines below fail when they shouldn't.)
  my %match_unique = map { $field_map->{$_} => $_ } @matches;
  @matches = values %match_unique;

  if (scalar(@matches) == 1) {
    return $field_map->{$matches[0]};
  }
  elsif (scalar(@matches) > 1) {
    return \@matches;
  }

  # Check if we match exactly one custom field, ignoring the cf_ on the
  # custom fields (to allow people to type things like "build" for
  # "cf_build").
  my %cfless;
  foreach my $name (@field_names) {
    my $no_cf = $name;
    if ($no_cf =~ s/^cf_//) {
      if ($field eq $no_cf) {
        return $field_map->{$name};
      }
      $cfless{$no_cf} = $name;
    }
  }

  # See if we match exactly one substring of any of the cf_-less fields.
  my @cfless_matches = grep { $_ =~ /^\Q$field\E/ } (keys %cfless);

  if (scalar(@cfless_matches) == 1) {
    my $match        = $cfless_matches[0];
    my $actual_field = $cfless{$match};
    return $field_map->{$actual_field};
  }
  elsif (scalar(@matches) > 1) {
    return \@matches;
  }

  return undef;
}

sub _special_field_syntax {
  my ($word, $negate) = @_;
  return unless defined($word);

  # P1-5 Syntax
  if ($word =~ m/^P(\d+)(?:-(\d+))?$/i) {
    my ($p_start, $p_end) = ($1, $2);
    my $legal_priorities = get_legal_field_values('priority');

    # If Pn exists explicitly, use it.
    my $start = firstidx { $_ eq "P$p_start" } @$legal_priorities;
    my $end;
    $end = firstidx { $_ eq "P$p_end" } @$legal_priorities if defined $p_end;

    # If Pn doesn't exist explicitly, then we mean the nth priority.
    if ($start == -1) {
      $start = max(0, $p_start - 1);
    }
    my $prios = $legal_priorities->[$start];

    if (defined $end) {

      # If Pn doesn't exist explicitly, then we mean the nth priority.
      if ($end == -1) {
        $end = min(scalar(@$legal_priorities), $p_end) - 1;
        $end = max(0, $end);    # Just in case the user typed P0.
      }
      ($start, $end) = ($end, $start) if $end < $start;
      $prios = join(',', @$legal_priorities[$start .. $end]);
    }

    addChart('priority', 'anyexact', $prios, $negate);
    return 1;
  }
  return 0;
}

sub _default_quicksearch_word {
  my ($word, $negate) = @_;
  return unless defined($word);

  if (!grep { lc($word) eq $_ } PRODUCT_EXCEPTIONS and length($word) > 2) {
    addChart('product', 'substring', $word, $negate);
  }

  if (!grep { lc($word) eq $_ } COMPONENT_EXCEPTIONS and length($word) > 2) {
    addChart('component', 'substring', $word, $negate);
  }

  my @legal_keywords = map($_->name, Bugzilla::Keyword->get_all);
  if (grep { lc($word) eq lc($_) } @legal_keywords) {
    addChart('keywords', 'substring', $word, $negate);
  }

  addChart('alias',             'substring', $word, $negate);
  addChart('short_desc',        'substring', $word, $negate);
  addChart('status_whiteboard', 'substring', $word, $negate);
  addChart('longdesc',          'substring', $word, $negate) if $ELASTIC;
  addChart('content', 'matches', _matches_phrase($word), $negate)
    if $fulltext && !$ELASTIC;

# BMO Bug 664124 - Include the crash signature (sig:) field in default quicksearches
  addChart('cf_crash_signature', 'substring', $word, $negate);
}

sub _handle_urls {
  my ($word, $negate) = @_;
  return unless defined($word);

  # URL field (for IP addrs, host.names,
  # scheme://urls)
  if ( $word =~ m/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/
    || $word =~ /^[A-Za-z]+(\.[A-Za-z]+)+/
    || $word =~ /:[\\\/][\\\/]/
    || $word =~ /localhost/
    || $word =~ /mailto[:]?/)

    # || $word =~ /[A-Za-z]+[:][0-9]+/ #host:port
  {
    addChart('bug_file_loc', 'substring', $word, $negate);
  }
}

###########################################################################
# Helpers
###########################################################################

# Quote and escape a phrase appropriately for a "content matches" search.
sub _matches_phrase {
  my ($phrase) = @_;
  return $phrase if $ELASTIC;
  $phrase =~ s/"/\\"/g;
  return "\"$phrase\"";
}

# Expand found prefixes to states or resolutions
sub matchPrefixes {
  my ($hr_states, $hr_resolutions, $word, $ar_check_states) = @_;
  return unless $word =~ /^[A-Z_]+(,[A-Z_]+)*\+?$/;

  my @ar_prefixes = split(/,/, $word);
  if ($ar_prefixes[-1] =~ s/\+$//) {
    Bugzilla->cgi->param(limit => 0);
  }
  my $ar_check_resolutions = get_legal_field_values('resolution');
  my $foundMatch           = 0;

  foreach my $prefix (@ar_prefixes) {
    foreach (@$ar_check_states) {
      if (/^$prefix/) {
        $$hr_states{$_} = 1;
        $foundMatch = 1;
      }
    }
    foreach (@$ar_check_resolutions) {
      if (/^$prefix/) {
        $$hr_resolutions{$_} = 1;
        $foundMatch = 1;
      }
    }
  }
  return $foundMatch;
}

# Negate comparison type
sub negateComparisonType {
  my $comparisonType = shift;

  if ($comparisonType eq 'anywords') {
    return 'nowords';
  }
  elsif ($comparisonType eq 'isempty') {
    return 'isnotempty';
  }
  return "not$comparisonType";
}

# Add a boolean chart
sub addChart {
  my ($field, $comparisonType, $value, $negate) = @_;

  $negate && ($comparisonType = negateComparisonType($comparisonType));
  makeChart("$chart-$and-$or", $field, $comparisonType, $value);
  if ($negate) {
    $and++;
    $or = 0;
  }
  else {
    $or++;
  }
}

# Create the CGI parameters for a boolean chart
sub makeChart {
  my ($expr, $field, $type, $value) = @_;

  my $cgi = Bugzilla->cgi;
  $cgi->param("field$expr", $field);
  $cgi->param("type$expr",  $type);
  $cgi->param("value$expr", $value);
}

1;
