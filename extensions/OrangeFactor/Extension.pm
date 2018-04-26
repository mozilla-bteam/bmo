# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OrangeFactor;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::User::Setting;
use Bugzilla::Constants;
use Bugzilla::Attachment;

use DateTime;

our $VERSION = '1.0';

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    my $user = Bugzilla->user;

    return unless ($file eq 'bug/show-header.html.tmpl'
                   || $file eq 'bug/edit.html.tmpl'
                   || $file eq 'bug_modal/header.html.tmpl'
                   || $file eq 'bug_modal/edit.html.tmpl');
    return unless ($user->id
                   && $user->settings->{'orange_factor'}->{'value'} eq 'on');

    # in the header we just need to set the var,
    # to ensure the css and javascript get included
    my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
    if ($bug && grep($_->name eq 'intermittent-failure', @{ $bug->keyword_objects })) {
        $vars->{'orange_factor'} = 1;
        $vars->{'date_start'} = ( DateTime->now() - DateTime::Duration->new( days => 7 ) )->ymd();
        $vars->{'date_end'} = DateTime->now->ymd();
    }
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting({
        name     => 'orange_factor',
        options  => ['on', 'off'],
        default  => 'off',
        category => 'User Interface'
    });
}

__PACKAGE__->NAME;
