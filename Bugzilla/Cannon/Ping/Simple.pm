# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Cannon::Ping::Simple;
use 5.10.1;
use Moo;

our $VERSION = '1';

with 'Bugzilla::Cannon::Ping';

sub _build_validator {
  my ($self) = @_;

  # For prototyping we use joi, but after protyping
  # $schema should be set to the file path or url of a json schema file.
  my $schema = joi->object->props({
    bug_id     => joi->integer->required->min(1),
    bug_status => joi->string->required,
    keywords   => joi->array->items(joi->string)->required,
    priority   => joi->string->required,
    resolution => joi->string,
    severity   => joi->string->required,
  })->strict;

  return JSON::Validator->new(schema => $schema);
}

sub _build_resultset {
  my ($self)  = @_;
  my $bugs    = $self->model->resultset('Bug');
  my $query   = { }; # match everything
  my $options = {
    join => ['keywords'],
    order_by => 'me.bug_id',
    group_by => 'me.bug_id',
    columns  => {
      bug_id     => 'me.bug_id',
      bug_status => 'me.bug_status',
      priority   => 'me.priority',
      resolution => 'me.resolution',
      severity   => 'me.severity',
      keywords   => { group_concat => 'keywords.name' },
    },
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
  };

  return $bugs->search_rs($query, $options);
}

1;
