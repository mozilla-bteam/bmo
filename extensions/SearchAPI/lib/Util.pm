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

use base qw(Exporter);

our @EXPORT_OK = qw(
  bug_to_hash
  comment_to_hash
  flag_to_hash
  named_params
  user_to_hash
);

use constant NAMED_PREFIX => ':';
use constant NAMED_SUFFIX => ':';

# Regex borrowed from SQL::Tokenizer
# https://metacpan.org/pod/SQL::Tokenizer
my $tokenize_re = qr{
    (
        (?:--|\#)[\ \t\S]*      # single line comments
        |
        (?:<>|<=>|>=|<=|==|=|!=|!|<<|>>|<|>|\|\||\||&&|&|-|\+|\*(?!/)|/(?!\*)|\%|~|\^|\?)
                                # operators and tests
        |
        [\[\]\(\),;.]            # punctuation (parenthesis, comma)
        |
        \'\'(?!\')              # empty single quoted string
        |
        \"\"(?!\"")             # empty double quoted string
        |
        "(?>(?:(?>[^"\\]+)|""|\\.)*)+"
                                # anything inside double quotes, ungreedy
        |
        `(?>(?:(?>[^`\\]+)|``|\\.)*)+`
                                # anything inside backticks quotes, ungreedy
        |
        '(?>(?:(?>[^'\\]+)|''|\\.)*)+'
                                # anything inside single quotes, ungreedy.
        |
        /\*[\ \t\r\n\S]*?\*/      # C style comments
        |
        (?:[\w:@]+(?:\.(?:\w+|\*)?)*)
                                # words, standard named placeholders, db.table.*, db.*
        |
        (?: \$_\$ | \$\d+ | \${1,2} )
                                # dollar expressions - eg $_$ $3 $$
        |
        \n                      # newline
        |
        [\t\ ]+                 # any kind of white spaces
    )
}smx;

# Some workflow borrowed from
# https://metacpan.org/pod/DBIx::Placeholder::Named
sub named_params {
  my ($query, $params) = @_;

  # Convert SQL statement in series of tokens
  my @query_tokens = $query =~ m{$tokenize_re}smxg;

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

sub bug_to_hash {
  my ($bug, $params) = @_;
  my $user = Bugzilla->user;

  my %item = (
    alias            => $bug->alias,
    id               => $bug->bug_id,
    is_confirmed     => $bug->everconfirmed,
    op_sys           => $bug->op_sys,
    platform         => $bug->rep_platform,
    priority         => $bug->priority,
    resolution       => $bug->resolution,
    severity         => $bug->bug_severity,
    status           => $bug->bug_status,
    summary          => $bug->short_desc,
    target_milestone => $bug->target_milestone,
    type             => $bug->bug_type,
    url              => $bug->bug_file_loc,
    version          => $bug->version,
    whiteboard       => $bug->status_whiteboard,
  );

  if ($params->{assignee}) {
    $item{assignee} = user_to_hash($bug->assigned_to);
  }
  if ($params->{blocks}) {
    $item{blocks} = $bug->blocked;
  }
  if ($params->{classification}) {
    $item{classification} = $bug->classification;
  }
  if ($params->{comments}) {
    my @result;
    my $comments = $bug->comments(
      {order => 'oldest_to_newest', after => $params->{new_since}});
    foreach my $comment (@$comments) {
      next if $comment->is_private && !$user->is_insider;
      push @result, comment_to_hash($comment);
    }
    $item{comments} = \@result;
  }
  if ($params->{component}) {
    $item{component} = $bug->component;
  }
  if ($params->{cc}) {
    $item{cc} = [map { user_to_hash($_) } @{$bug->cc_users}];
  }
  if ($params->{creation_time}) {
    $item{creation_time} = $bug->creation_ts;
  }
  if ($params->{creator}) {
    $item{creator_detail} = user_to_hash($bug->reporter);
  }
  if ($params->{depends_on}) {
    $item{depends_on} = $bug->dependson;
  }
  if ($params->{description}) {
    my $comment = Bugzilla::Comment->match({bug_id => $bug->id, LIMIT => 1})->[0];
    $item{description}
      = ($comment && (!$comment->is_private || Bugzilla->user->is_insider))
      ? $comment->body
      : '';
  }
  if ($params->{dupe_of}) {
    $item{dupe_of} = $bug->dup_id;
  }
  if ($params->{duplicates}) {
    $item{duplicates} = $bug->duplicates;
  }
  if ($params->{groups}) {
    $item{groups} = $bug->groups_in;
  }
  if ($params->{is_open}) {
    $item{is_open} = $bug->status->is_open ? 1 : 0;
  }
  if ($params->{keywords}) {
    $item{keywords} = [map { $_->name } @{$bug->keyword_objects}];
  }
  if ($params->{last_change_time}) {
    $item{last_change_time} = $bug->delta_ts;
  }
  if ($params->{last_change_time_non_bot}) {
    $item{last_change_time_non_bot} = $bug->delta_ts_non_bot;
  }
  if ($params->{product}) {
    $item{product} = $bug->product;
  }
  if ($params->{qa_contact}) {
    if ($bug->qa_contact) {
      $item{qa_contact} = user_to_hash($bug->qa_contact);
    }
  }
  if ($params->{triage_owner}) {
    my $triage_owner = $bug->component_obj->triage_owner;
    if ($triage_owner->login) {
      $item{triage_owner} = user_to_hash($triage_owner);
    }
  }
  if ($params->{see_also}) {
    $item{see_also} = [map { $_->name } @{$bug->see_also}];
  }
  if ($params->{flags}) {
    $item{flags} = [map { flag_to_hash($_) } @{$bug->flags}];
  }

  # Regressions
  if (Bugzilla->params->{use_regression_fields}) {
    if ($params->{regressed_by}) {
      $item{regressed_by} = $bug->regressed_by;
    }
    if ($params->{regressions}) {
      $item{regressions} = $bug->regresses;
    }
  }

  # Custom fields
  my @custom_fields = Bugzilla->active_custom_fields(
    {
      product   => $bug->product_obj,
      component => $bug->component_obj,
      bug_id    => $bug->id
    },
  );
  foreach my $field (@custom_fields) {
    my $name = $field->name;
    next if !$params->{$name};
    $item{$name} = $bug->$name;
  }

  # Timetracking fields
  if ($user->is_timetracker) {
    if ($params->{estimated_time}) {
      $item{estimated_time} = $bug->estimated_time;
    }
    if ($params->{remaining_time}) {
      $item{remaining_time} = $bug->remaining_time;
    }
    if ($params->{deadline}) {
      $item{deadline} = $bug->deadline;
    }
    if ($params->{actual_time}) {
      $item{actual_time} = $bug->actual_time;
    }
  }

  # Bug accessibility
  if ($params->{is_cc_accessible}) {
    $item{is_cc_accessible} = $bug->cclist_accessible ? 1 : 0;
  }
  if ($params->{is_creator_accessible}) {
    $item{is_creator_accessible} = $bug->reporter_accessible ? 1 : 0;
  }

  # Bug mentors
  if ($params->{mentors}) {
    $item{mentors} = [map { user_to_hash($_) } @{$bug->mentors}];
  }

  return \%item;
}

sub user_to_hash {
  my ($user) = @_;
  my $item = {
    id        => $user->id,
    real_name => $user->name,
    nick      => $user->nick,
    name      => $user->login,
    email     => $user->email,
  };
  return $item;
}

sub flag_to_hash {
  my ($flag) = @_;

  my $item = {
    id                => $flag->id,
    name              => $flag->name,
    type_id           => $flag->type_id,
    creation_date     => $flag->creation_date,
    modification_date => $flag->modification_date,
    status            => $flag->status
  };

  foreach my $field (qw(setter requestee)) {
    my $field_id = $field . "_id";
    $item->{$field} = user_to_hash($flag->$field) if $flag->$field_id;
  }

  return $item;
}

1;
