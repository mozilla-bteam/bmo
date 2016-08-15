# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::MozProjectReview;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::User;
use Bugzilla::Group;
use Bugzilla::Error;
use Bugzilla::Constants;

our $VERSION = '0.01';

# these users will be cc'd to the parent bug when the corresponding child bug
# is created, as well as the child bug.
our %auto_cc = (
    'legal'                   => ['liz@mozilla.com'],
    'finance'                 => ['waoieong@mozilla.com', 'mcristobal@mozilla.com', 'echoe@mozilla.com'],
    'privacy-vendor'          => ['smartin@mozilla.com'],
    'privacy-project'         => ['ahua@mozilla.com'],
    'privacy-tech'            => ['ahua@mozilla.com'],
    'policy-business-partner' => ['smartin@mozilla.com']
);

sub post_bug_after_creation {
    my ($self, $args) = @_;
    my $vars      = $args->{'vars'};
    my $bug       = $vars->{'bug'};
    my $timestamp = $args->{'timestamp'};
    my $user      = Bugzilla->user;
    my $params    = Bugzilla->input_params;
    my $template  = Bugzilla->template;

    return if !($params->{format}
                && $params->{format} eq 'moz-project-review'
                && $bug->component eq 'Project Review');

    # do a match if applicable
    Bugzilla::User::match_field({
        'legal_cc' => { 'type' => 'multi' }
    });

    my ($do_sec_review, $do_legal, $do_finance, $do_data_compliance);

    if ($params->{'mozilla_data'} eq 'Yes') {
        $do_legal = 1;
        $do_data_compliance = 1;
        $do_sec_review = 1;
    }

    if ($params->{'separate_party'} eq 'Yes') {
        if ($params->{'relationship_type'} ne 'Hardware Purchase') {
            $do_legal = 1;
        }

        if ($params->{'data_access'} eq 'Yes') {
            $do_data_compliance = 1;
            $do_legal = 1;
            $do_sec_review = 1;
        }

        if ($params->{'data_access'} eq 'Yes'
            && $params->{'privacy_policy_vendor_user_data'} eq 'Yes')
        {
            $do_data_compliance = 1;
        }

        if ($params->{'vendor_cost'} eq '> $25,000' 
            || ($params->{'vendor_cost'} eq '<= $25,000'
                && $params->{'po_needed'} eq 'Yes')) 
        {
            $do_finance = 1;
        }
    }

    my ($sec_review_bug, $legal_bug, $finance_bug, $data_compliance_bug,
        $error, @dep_comment, @dep_errors, @send_mail);

    # Common parameters always passed to _file_child_bug
    # bug_data and template_suffix will be different for each bug
    my $child_params = {
        parent_bug    => $bug,
        template_vars => $vars,
        dep_comment   => \@dep_comment,
        dep_errors    => \@dep_errors,
        send_mail     => \@send_mail,
    };

    if ($do_sec_review) {
        $child_params->{'bug_data'} = {
            short_desc   => 'RRA: ' . $bug->short_desc,
            product      => 'Enterprise Information Security',
            component    => 'Rapid Risk Analysis',
            bug_severity => 'normal',
            groups       => [ 'mozilla-employee-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };
        $child_params->{'template_suffix'} = 'sec-review';
        _file_child_bug($child_params);
    }

    if ($do_legal) {
        my $component = 'General';

        if ($params->{separate_party} eq 'Yes'
            && $params->{relationship_type})
        {
            $component = ($params->{relationship_type} eq 'Other'
                            || $params->{relationship_type} eq 'Hardware Purchase')
                         ? 'General'
                         : $params->{relationship_type};
        }

        my $legal_summary = "Legal Review: ";
        $legal_summary .= $params->{legal_other_party} . " - " if $params->{legal_other_party};
        $legal_summary .= $bug->short_desc;

        $child_params->{'bug_data'} = {
            short_desc   => $legal_summary,
            product      => 'Legal',
            component    => $component,
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'legal' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
            cc           => $params->{'legal_cc'},
        };
        $child_params->{'template_suffix'} = 'legal';
        _file_child_bug($child_params);
    }

    if ($do_finance) {
        $child_params->{'bug_data'} = {
            short_desc   => 'Finance Review: ' . $bug->short_desc,
            product      => 'Finance',
            component    => 'Purchase Request Form',
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'finance' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };
        $child_params->{'template_suffix'} = 'finance';
        _file_child_bug($child_params);
    }

    if ($do_data_compliance) {
        $child_params->{'bug_data'} = {
            short_desc   => 'Data Compliance Review: ' . $bug->short_desc,
            product      => 'Data Compliance',
            component    => 'General',
            bug_severity => 'normal',
            priority     => '--',
            bug_severity => $params->{data_comp_urgency},
            groups       => [ 'mozilla-employee-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            cf_due_date  => $params->{release_date},
            blocked      => $bug->bug_id,
        };
        $child_params->{'template_suffix'} = 'data-compliance';
        _file_child_bug($child_params);
    }

    if (scalar @dep_errors) {
        warn "[Bug " . $bug->id . "] Failed to create additional moz-project-review bugs:\n" .
             join("\n", @dep_errors);
        $vars->{'message'} = 'moz_project_review_creation_failed';
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
        my $full_template = "bug/create/comment-moz-project-review-$template_suffix.txt.tmpl";
        Bugzilla->template->process($full_template, $template_vars, \$comment)
            || ThrowTemplateError(Bugzilla->template->error());
        $bug_data->{'comment'} = $comment;
        if (exists $auto_cc{$template_suffix}) {
            $bug_data->{'cc'} = $auto_cc{$template_suffix};
        }
        if ($new_bug = Bugzilla::Bug->create($bug_data)) {
            my $set_all = {
                dependson => { add => [ $new_bug->bug_id ] }
            };
            if (exists $auto_cc{$template_suffix}) {
                $set_all->{'cc'} = { add => $auto_cc{$template_suffix} };
            }
            $parent_bug->set_all($set_all);
            $parent_bug->update($parent_bug->creation_ts);
        }
    };

    if ($@ || !($new_bug && $new_bug->{'bug_id'})) {
        push(@$dep_comment, "Error creating $template_suffix review bug");
        push(@$dep_errors, "$template_suffix : $@") if $@;
        # Since we performed Bugzilla::Bug::create in an eval block, we
        # need to manually rollback the commit as this is not done
        # in Bugzilla::Error automatically for eval'ed code.
        Bugzilla->dbh->bz_rollback_transaction();
    }
    else {
        push(@$send_mail, $new_bug->id);
        push(@$dep_comment, "Bug " . $new_bug->id . " - " . $new_bug->short_desc);
    }

    undef $@;
    Bugzilla->error_mode($old_error_mode);
}

__PACKAGE__->NAME;
