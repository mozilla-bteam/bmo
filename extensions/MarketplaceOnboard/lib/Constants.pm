# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MarketplaceOnboard::Constants;

use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw( DEP_MAP BUG_MAP );

use constant DEP_MAP => {

};

use constant BUG_MAP => [
    {
        name        => 'bug2',
        form_fields => { region => 'Other' },
        bug_data    => {
            short_desc   => '[Legal / L10N] Legal Assessment and Translations for new Operator / Region',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'udevi@mozilla.com',
            cc           => ['marketplace-programs@mozilla.com', 'pmo@mozilla.com'],
        },
        blocks => ['bug1'],
    },
    {
        name        => 'bug3',
        form_fields => { language => 'Other' },
        bug_data    => {
            short_desc   => '[l10n] Localized Privacy Policy for New Market launch',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'pmo@mozilla.com',
            cc           => ['flod@mozilla.com', 'pascal@mozilla.com'],
        },
        blocks => ['bug2']
    },
    {
        name        => 'bug4',
        form_fields => { language => 'Other' },
        bug_data    => {
            short_desc   => '[l10n] Localized Terms of Service for New Market launch',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'pmo@mozilla.com',
            cc           => ['flod@mozilla.com', 'pascal@mozilla.com'],
        },
        blocks => ['bug2'],
    },
    {
        name        => 'bug5',
        form_fields => { language => 'Other' },
        bug_data => {
            short_desc   => '[l10n] Localized Developer Agreement for New Market launch',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'pmo@mozilla.com',
            cc           => ['flod@mozilla.com', 'pascal@mozilla.com'],

        },
        blocks => ['bug2'],
    },
    {
        name        => 'bug6',
        form_fields => { language => 'Other' },
        bug_data => {
            short_desc   => '[L10N] Add new localization in Marketplace',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'pmo@mozilla.com',
            cc           => ['marketplace-programs@mozilla.com', 'mp-product@mozilla.com', 'clouserw@mozilla.com'],
        },
        blocks => ['bug1'],
    },
    {
        name        => 'bug8',
        form_fields => { region => 'Other' },
        bug_data    => {
            short_desc   => '[Marketplace] Enable new Operator / Region / Language in Marketplace',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'marketplace-programs@mozilla.com',
            cc           => ['marketplace-product@mozilla.com'],
        },
        blocks => ['bug1'],

    },
    {
        name        => 'bug7',
        form_fields => { language => 'Other' },
        bug_data => {
            short_desc   => '[dev] Enable new Language in Marketplace (dev + productions)',
            product      => 'Marketplace',
            component    => 'General',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '1.0',
        },
        blocks => ['bug6','bug8'],
    },
    {
        name        => 'bug13',
        form_fields => { language => 'Other' },
        bug_data    => {
            short_desc   => '[ESRB / L10N] Translate Privacy Policy and Terms of Service into new language',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
        },
        blocks => ['bug6'],
    },
    {
        name        => 'bug14',
        form_fields => { language => 'Other' },
        bug_data    => {
            short_desc   => '[UX / L10N] update affiliate / marketing badges in new language',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'marketplace-ux@mozilla.com',
        },
        blocks => ['bug6'],
    },
    {
        name        => 'bug15',
        form_fields => { language => 'Other' },
        bug_data    => {
            short_desc   => '[MDN] Update Content Review Guidelines w/ new localization',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'jypenator@gmail.com',
            cc           => ['pmo@mozilla.com', 'aspivak@mozilla.com'],
        },
        blocks => ['bug6'],
    },
    {
        name        => 'bug16',
        form_fields => { region => 'Other' },
        bug_data => {
            short_desc   => '[dev] Enable new Region in Marketplace',
            product      => 'Marketplace',
            component    => 'General',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '1.0',
        },
        blocks => ['bug8'],
    },
    {
        name        => 'bug17',
        form_fields => { want_for_launch => 'Yes' },
        bug_data    => {
            short_desc   => '[content] work with operator / oem to complete Operator Shelf',
            product      => 'Tracking',
            component    => 'User Story',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '---',
            assigned_to  => 'sdevaney@mozilla.com',
            cc           => ['marketplace-programs@mozilla.com'],
        },
        blocks => ['bug1'],
    },
    {
        name        => 'bug18',
        form_fields => { want_for_launch => 'Yes' },
        bug_data    => {
            short_desc   => '[dev] Enable new Operator / OEM Shelf in Marketplace',
            product      => 'Marketplace',
            component    => 'General',
            bug_severity => 'normal',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => '1.0',
        },
        blocks => ['bug1','bug6']
    },
];

1;
