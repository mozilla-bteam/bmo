# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Cannon::Ping::Simple;
use 5.10.1;
use Moo;
use JSON::Validator qw(joi);

with 'Bugzilla::Cannon::Ping';

sub _build_validator {
  my ($self) = @_;
  my $schema = joi->object->props({
    bug_id     => joi->integer->required->min(1),
    bug_status => joi->string->required,
    resolution => joi->string,
    priority   => joi->string->required,
    severity   => joi->string->required,
  });

  return JSON::Validator->new(schema => $schema);
}

sub _build_resultset {
  my ($self)  = @_;
  my $bugs    = $self->model->resultset('Bug');
  my $query   = { }; # match everything
  my $options = {
    order_by => 'bugs.bug_id',
    columns  => {
      bug_id     => 'me.bug_id',
      bug_status => 'me.bug_status',
      resolution => 'me.resolution',
      priority   => 'me.priority',
      severity   => 'me.severity',
    },
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
  };

  return $bugs->search_rs($query, $options);
}

1;
