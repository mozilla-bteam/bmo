# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::RegressedByTypeKeyword;

use 5.10.1;
use Moo;

use Bugzilla::Keyword;

sub evaluate_create {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};
  my $dbh       = Bugzilla->dbh;

  return unless @{$bug->regressed_by};

  # When the new bug is created with a value for `regressed by`, we require
  # that the bug has the 'regression' keyword added.
  if (!$bug->has_keyword('regression')) {
    my $keyword_obj = Bugzilla::Keyword->new({name => 'regression'});
    if ($keyword_obj) {
      $dbh->do('INSERT INTO keywords (bug_id, keywordid) VALUES (?, ?)',
        undef, $bug->id, $keyword_obj->id);
      delete $bug->{'keyword_objects'};    # Clear current keywords so they have to be reloaded.
    }
  }

  # When the new bug is created with a value for `regressed by`, we require
  # that the bug type be set to 'defect'.
  if ($bug->bug_type ne 'defect') {
    $dbh->do('UPDATE bugs SET bug_type = ? WHERE bug_id = ?',
      undef, 'defect', $bug->id);
    $bug->{bug_type} = 'defect';
  }
}

sub evaluate_change {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};
  my $changes   = $args->{changes};
  my $dbh       = Bugzilla->dbh;

  return unless (@{$bug->regressed_by} && exists $changes->{regressed_by});

  # If the user has added a 'regressed by' value to the bug, we then require 
  # that the bug has the 'regression' keyword. If for some reason the user
  # also added the keyword, then we can skip this.
  if (!$bug->has_keyword('regression')
    && !(exists $changes->{keywords}
      && $changes->{keywords}->[1] =~ /\bregression\b/))
  {
    my $keyword_obj = Bugzilla::Keyword->new({name => 'regression'});
    if ($keyword_obj) {
      $dbh->do('INSERT INTO keywords (bug_id, keywordid) VALUES (?, ?)',
        undef, $bug->id, $keyword_obj->id);
      delete $bug->{'keyword_objects'};    # Clear current keywords so they have to be reloaded.
      $changes->{keywords} ||= [];
      $changes->{keywords}->[0]
        = ($changes->{keywords}->[0] ? $changes->{keywords}->[0] : '');
      $changes->{keywords}->[1]
        = ($changes->{keywords}->[1]
        ? $changes->{keywords}->[1] . ', regression'
        : 'regression');
    }
  }

  # If the user has added a 'regressed_by' value to the bug, we then require
  # the bug type to be set to 'defect'. If for some reason the user is setting
  # the bug type also to 'defect', then we can skip this.
  if ($bug->bug_type ne 'defect'
    && !(exists $changes->{bug_type} && $changes->{bug_type}->[1] eq 'defect'))
  {
    $dbh->do('UPDATE bugs SET bug_type = ? WHERE bug_id = ?',
      undef, 'defect', $bug->id);
    $changes->{bug_type} = [$bug->bug_type, 'defect'];
    $bug->{bug_type}     = 'defect';
  }
}

1;
