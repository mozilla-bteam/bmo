# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::InlineHistory;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::User::Setting;
use Bugzilla::Constants;
use Bugzilla::Attachment;
use Bugzilla::Util ();

our $VERSION = '1.5';

# don't show inline history for bugs with lots of changes
use constant MAXIMUM_ACTIVITY_COUNT => 500;

# don't show really long values
use constant MAXIMUM_VALUE_LENGTH => 256;

sub template_before_create {
  my ($self, $args) = @_;
  $args->{config}->{FILTERS}->{ih_short_value} = sub {
    my ($str) = @_;
    return
      length($str) <= MAXIMUM_VALUE_LENGTH
      ? $str
      : substr($str, 0, MAXIMUM_VALUE_LENGTH - 3) . '...';
  };
}

sub template_before_process {
  my ($self, $args) = @_;
  my $file = $args->{'file'};
  my $vars = $args->{'vars'};

  return if $file ne 'bug/edit.html.tmpl';

  my $user = Bugzilla->user;
  my $dbh  = Bugzilla->dbh;
  return
    unless $user->id && $user->settings->{'inline_history'}->{'value'} eq 'on';

  # note: bug/edit.html.tmpl doesn't support multiple bugs
  my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
  my $bug_id = $bug->id;

  # build bug activity
  my ($activity)
    = $bug->can('get_activity')
    ? $bug->get_activity()
    : Bugzilla::Bug::GetBugActivity($bug_id);
  $activity = _add_duplicates($bug_id, $activity);

  if (scalar @$activity > MAXIMUM_ACTIVITY_COUNT) {
    $activity                  = [];
    $vars->{'ih_activity'}     = 0;
    $vars->{'ih_activity_max'} = 1;
    return;
  }

  # allow other extensions to alter history
  Bugzilla::Hook::process('inline_history_activtiy', {activity => $activity});

  my %attachment_cache;
  foreach my $attachment (@{$bug->attachments}) {
    $attachment_cache{$attachment->id} = $attachment;
  }

# build a list of bugs we need to check visibility of, so we can check with a single query
  my %visible_bug_ids;

  # augment and tweak
  foreach my $operation (@$activity) {

    # make operation.who an object
    $operation->{who}
      = Bugzilla::User->new({name => $operation->{who}, cache => 1});

    for (my $i = 0; $i < scalar(@{$operation->{changes}}); $i++) {
      my $change = $operation->{changes}->[$i];

      # make an attachment object
      if ($change->{attachid}) {
        $change->{attach} = $attachment_cache{$change->{attachid}};
      }

      # empty resolutions are displayed as --- by default
      # make it explicit here to enable correct display of the change
      if ($change->{fieldname} eq 'resolution') {
        $change->{removed} = '---' if $change->{removed} eq '';
        $change->{added}   = '---' if $change->{added} eq '';
      }

      # make boolean fields true/false instead of 1/0
      my ($table, $field) = ('bugs', $change->{fieldname});
      if ($field =~ /^([^\.]+)\.(.+)$/) {
        ($table, $field) = ($1, $2);
      }
      my $column = $dbh->bz_column_info($table, $field);
      if ($column && $column->{TYPE} eq 'BOOLEAN') {
        $change->{removed} = '';
        $change->{added} = $change->{added} ? 'true' : 'false';
      }

      my $field_obj;
      if ($change->{fieldname} =~ /^cf_/) {
        $field_obj = Bugzilla::Field->new({name => $change->{fieldname}, cache => 1});
        $change->{fieldtype} = $field_obj->type;
      }

      # identify buglist changes
      if ($change->{fieldname} =~ /^(dependson|blocked|regress(ed_by|es)|dupe)$/
        || ($field_obj && $field_obj->type == FIELD_TYPE_BUG_ID))
      {
        $change->{buglist} = 1;
        foreach my $what (qw(removed added)) {
          my @buglist = split(/[\s,]+/, $change->{$what});
          foreach my $id (@buglist) {
            if ($id && $id =~ /^\d+$/) {
              $visible_bug_ids{$id} = 1;
            }
          }
        }
      }

      # split see-also
      if ($change->{fieldname} eq 'see_also') {
        my $url_base = Bugzilla->localconfig->{urlbase};
        foreach my $f (qw( added removed )) {
          my @values;
          foreach my $value (split(/, /, $change->{$f})) {
            my ($bug_id)
              = substr($value, 0, length($url_base)) eq $url_base
              ? $value =~ /id=(\d+)$/
              : undef;
            push @values, {url => $value, bug_id => $bug_id,};
          }
          $change->{$f} = \@values;
        }
      }

      # split multiple flag changes (must be processed last)
      if ($change->{fieldname} eq 'flagtypes.name') {
        my @added   = split(/, /, $change->{added});
        my @removed = split(/, /, $change->{removed});
        next if scalar(@added) <= 1 && scalar(@removed) <= 1;

        # remove current change
        splice(@{$operation->{changes}}, $i, 1);

        # restructure into added/removed for each flag
        my %flags;
        foreach my $added (@added) {
          my ($value, $name) = $added =~ /^((.+).)$/;
          next unless defined $name;
          $flags{$name}{added} = $value;
          $flags{$name}{removed} |= '';
        }
        foreach my $removed (@removed) {
          my ($value, $name) = $removed =~ /^((.+).)$/;
          next unless defined $name;
          $flags{$name}{added} |= '';
          $flags{$name}{removed} = $value;
        }

        # clone current change, modify and insert
        foreach my $flag (sort keys %flags) {
          my $flag_change = {};
          foreach my $key (keys %$change) {
            $flag_change->{$key} = $change->{$key};
          }
          $flag_change->{removed} = $flags{$flag}{removed};
          $flag_change->{added}   = $flags{$flag}{added};
          splice(@{$operation->{changes}}, $i, 0, $flag_change);
        }
        $i--;
      }
    }
  }

  $user->visible_bugs([keys %visible_bug_ids]);

  $vars->{'ih_activity'} = $activity;
}

sub _add_duplicates {

  # insert 'is a dupe of this bug' comment to allow js to display
  # as activity

  my ($bug_id, $activity) = @_;

  # we're ignoring pre-bugzilla 3.0 ".. has been marked as a duplicate .."
  # comments because searching each comment's text is expensive.  these
  # legacy comments will not be visible at all in the bug's comment/activity
  # stream.  bug 928786 deals with migrating those comments to be stored as
  # CMT_HAS_DUPE instead.

  my $dbh = Bugzilla->dbh;
  my $sth = $dbh->prepare("
        SELECT profiles.login_name, "
      . $dbh->sql_date_format('bug_when', '%Y.%m.%d %H:%i:%s') . ",
               extra_data
          FROM longdescs
               INNER JOIN profiles ON profiles.userid = longdescs.who
         WHERE bug_id = ? AND type = ?
         ORDER BY bug_when
    ");
  $sth->execute($bug_id, CMT_HAS_DUPE);

  while (my ($who, $when, $dupe_id) = $sth->fetchrow_array) {
    my $entry = {
      'when'    => $when,
      'who'     => $who,
      'changes' => [{
        'removed'   => '',
        'added'     => $dupe_id,
        'attachid'  => undef,
        'fieldname' => 'dupe',
        'dupe'      => 1,
      }],
    };
    push @$activity, $entry;
  }

  return [sort { $a->{when} cmp $b->{when} } @$activity];
}

sub install_before_final_checks {
  my ($self, $args) = @_;
  add_setting({
    name     => 'inline_history',
    options  => ['on', 'off'],
    default  => 'off',
    category => 'Bug Editing'
  });
}

__PACKAGE__->NAME;
