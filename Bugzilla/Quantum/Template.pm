# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Template;
use 5.10.1;
use Moo;

has 'controller' => (
    is       => 'ro',
    required => 1,
);

has 'template' => (
    is       => 'ro',
    required => 1,
    handles  => ['error', 'get_format'],
);

sub process {
    my ($self, $file, $vars, $output) = @_;

    if (@_ < 4) {
        $self->controller->stash->{vars} = $vars;
        $self->controller->render(template => $file, handler => 'bugzilla');
        return 1;
    }
    elsif (@_ == 4) {
        return $self->template->process($file, $vars, $output);
    }
    else {
        die __PACKAGE__ . '->process() called with too many arguments';
    }
}

1;