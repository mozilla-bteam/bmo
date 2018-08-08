#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Mailer;
use Bugzilla::Report::SecurityRisk;

use DateTime;
use URI;

BEGIN { Bugzilla->extensions }
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $html;
my $template = Bugzilla->template();
my $start_date = DateTime->today()->subtract(years => 3);
my $end_date = DateTime->today()->subtract(years => 2, months => 6);
my $report_week = $end_date->ymd('-');
my $products = [
    # Frontend
    'Firefox',
    'DevTools',
    'Toolkit',
    'WebExtensions',
    # Platform
    'Core',
    'Firefox Build System',
    'NSPR',
    'NSS',
    # Mobile
    'Firefox for Android',
    'Firefox for iOS',
    'Focus',
    'Focus-iOS',
    'Emerging Markets',
    # Others
    'External Software Affecting Firefox',
    'Cloud Services',
    'Pocket',
];
my $sec_keywords = [
    'sec-critical',
    'sec-high'
];
my $report = Bugzilla::Report::SecurityRisk->new(
    start_date => $start_date,
    end_date => $end_date,
    products => $products,
    sec_keywords => $sec_keywords
);
my $vars = {
    urlbase => Bugzilla->localconfig->{urlbase},
    report_week => $report_week,
    products => $products,
    sec_keywords => $sec_keywords,
    results => $report->results,
    build_bugs_link => sub {
        my ($arr, $product) = @_;
        my $uri = URI->new(Bugzilla->localconfig->{urlbase} . 'buglist.cgi');
        $uri->query_param(bug_id => (join ',', @$arr));
        $uri->query_param(product => $product) if $product;
        return $uri->as_string;
    }
};

$template->process('reports/email/security-risk.html.tmpl', $vars, \$html)
            || ThrowTemplateError($template->error());

# For now, only send HTML email.
my $email = Email::MIME->create(
    header_str => [
        From => Bugzilla->params->{'mailfrom'},
        To => 'vagrant@bmo-web.vm',
        Subject => "Security Bugs Report for $report_week"
    ],
    attributes => {
        content_type => 'text/html',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable',
    },
    body_str => $html,
);

MessageToMTA($email);
