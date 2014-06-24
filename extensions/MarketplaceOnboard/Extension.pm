# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::MarketplaceOnboard;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::User;
use Bugzilla::Group;
use Bugzilla::Error;
use Bugzilla::Constants;

use Bugzilla::Extension::MarketplaceOnboard::Constants;

use Data::Dumper;

our $VERSION = '0.01';

sub post_bug_after_creation {
    my ($self, $args) = @_;
    my $vars      = $args->{'vars'};
    my $bug       = $vars->{'bug'};
    my $timestamp = $args->{'timestamp'};
    my $user      = Bugzilla->user;
    my $params    = Bugzilla->input_params;
    my $template  = Bugzilla->template;

    return if !($params->{format}
                && $params->{format} eq 'marketplace-onboard'
                && $bug->component eq 'User Story');

    # Common parameters always passed to _file_child_bug
    # bug_data and template_suffix will be different for each bug
    my (@dep_comment, @dep_errors, @send_mail, %bug_map);

    my $child_params = {
        parent_bug    => $bug,
        template_vars => $vars,
        dep_comment   => \@dep_comment,
        dep_errors    => \@dep_errors,
        send_mail     => \@send_mail,
    };

    # Loop through each of the bug definitions to determine which ones to create
    foreach my $bug_def (@{ BUG_MAP() }) {
        my $form_fields = $bug_def->{form_fields};
        foreach my $field (keys %$form_fields) {
            if ($params->{$field} eq $form_fields->{$field}) {
                $child_params->{bug_data} = $bug_def->{bug_data};

                # Will fix when proper accounts are given
                delete $child_params->{bug_data}->{assigned_to};
                delete $child_params->{bug_data}->{cc};

                # Add mo-emp-conf group to all created bugs
                $child_params->{bug_data}->{groups} = ['mozilla-employee-confidential'];

                # Add special dependencies
                if (exists $bug_def->{blocks}) {
                    my @block_ids;
                    foreach my $block_name (@{ $bug_def->{blocks} }) {
                        if (exists $bug_map{$block_name}) {
                            push(@block_ids, $bug_map{$block_name});
                        }
                    }
                    $child_params->{bug_data}->{blocked} = \@block_ids;
                }

                $child_params->{template_suffix} = $bug_def->{name};
                my $new_bug = _file_child_bug($child_params);
                $bug_map{$bug_def->{name}} = $new_bug->id if $new_bug;

                last;
            }
        }
    }

    if (scalar @dep_errors) {
        warn "[Bug " . $bug->id . "] Failed to create additional marketplace-onboard bugs:\n" .
             join("\n", @dep_errors);
        $vars->{'message'} = 'marketplace_onboard_creation_failed';
    }

    if (scalar @dep_comment) {
        my $comment = join("\n", @dep_comment);
        if (scalar @dep_errors) {
            $comment .= "\n\nSome errors occurred creating dependent bugs and have been recorded";
        }
        $bug->add_comment($comment);
        $bug->update($bug->creation_ts);
    }

    foreach my $bug_id (@send_mail) {
        Bugzilla::BugMail::Send($bug_id, { changer => Bugzilla->user });
    }
}

sub _file_child_bug {
    my ($params) = @_;
    my ($parent_bug, $template_vars, $template_suffix, $bug_data, $dep_comment, $dep_errors, $send_mail)
        = @$params{qw(parent_bug template_vars template_suffix bug_data dep_comment dep_errors send_mail)};

    my $old_error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);

    my $new_bug;
    eval {
        my $comment;
        my $full_template = "bug/create/comment-marketplace-onboard-$template_suffix.txt.tmpl";
        Bugzilla->template->process($full_template, $template_vars, \$comment)
            || ThrowTemplateError(Bugzilla->template->error());
        $bug_data->{'comment'} = $comment;
        if ($new_bug = Bugzilla::Bug->create($bug_data)) {
            my $set_all = {
                dependson => { add => [ $new_bug->bug_id ] }
            };
            $parent_bug->set_all($set_all);
            $parent_bug->update($parent_bug->creation_ts);
        }
    };

    if ($@ || !($new_bug && $new_bug->{'bug_id'})) {
        push(@$dep_comment, "Error creating $template_suffix bug");
        push(@$dep_errors, "$template_suffix : $@") if $@;
        # Since we performed Bugzilla::Bug::create in an eval block, we
        # need to manually rollback the commit as this is not done
        # in Bugzilla::Error automatically for eval'ed code.
        Bugzilla->dbh->bz_rollback_transaction();
        return undef;
    }
    else {
        push(@$send_mail, $new_bug->id);
        push(@$dep_comment, "Bug " . $new_bug->id . " - " . $new_bug->short_desc);
    }

    undef $@;
    Bugzilla->error_mode($old_error_mode);

    return $new_bug;
}

__PACKAGE__->NAME;
