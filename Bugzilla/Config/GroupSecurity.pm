# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::GroupSecurity;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Group;

our $sortkey = 900;

sub get_param_list {
    my $class = shift;

    my @param_list = (
        {
            name    => 'makeproductgroups',
            type    => 'b',
            default => 0
        },

        {
            name    => 'chartgroup',
            type    => 's',
            choices => \&get_all_group_names,
            default => 'editbugs',
            checker => \&check_group
        },

        {
            name    => 'insidergroup',
            type    => 's',
            choices => \&get_all_group_names,
            default => '',
            checker => \&check_group
        },

        {
            name    => 'timetrackinggroup',
            type    => 's',
            choices => \&get_all_group_names,
            default => 'editbugs',
            checker => \&check_group
        },

        {
            name    => 'querysharegroup',
            type    => 's',
            choices => \&get_all_group_names,
            default => 'editbugs',
            checker => \&check_group
        },

        {
            name    => 'comment_taggers_group',
            type    => 's',
            choices => \&get_all_group_names,
            default => 'editbugs',
            checker => \&check_comment_taggers_group
        },

        {
            name    => 'debug_group',
            type    => 's',
            choices => \&get_all_group_names,
            default => 'admin',
            checker => \&check_group
        },

        {
            name    => 'usevisibilitygroups',
            type    => 'b',
            default => 0
        },

        {
            name    => 'strict_isolation',
            type    => 'b',
            default => 0
        },
        {
            name    => 'always_filleable_groups',
            type    => 'l',
            default => join(", ", qw(
                addons-security
                bugzilla-security
                client-services-security
                consulting
                core-security
                finance
                infra
                infrasec
                l20n-security
                marketing-private
                mozilla-confidential
                mozilla-employee-confidential
                mozilla-foundation-confidential
                mozilla-engagement
                mozilla-messaging-confidential
                partner-confidential
                payments-confidential
                tamarin-security
                websites-security
                webtools-security
            )),
        }
    );
    return @param_list;
}



1;
