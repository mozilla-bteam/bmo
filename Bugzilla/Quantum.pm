# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

use CGI::Compile; # Needed for its exit() overload
use Bugzilla::Logging;
use Bugzilla::Quantum::Template;
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::SES;
use Bugzilla::Quantum::Static;

use Bugzilla ();
use Bugzilla::Constants qw(bz_locations);
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Cwd qw(realpath);

use MojoX::Log::Log4perl::Tiny;

has 'static' => sub { Bugzilla::Quantum::Static->new };

sub startup {
    my ($self) = @_;

    DEBUG("Starting up");
    $self->plugin('Bugzilla::Quantum::Plugin::Glue');
    $self->plugin('Bugzilla::Quantum::Plugin::Hostage');
    $self->plugin('Bugzilla::Quantum::Plugin::BlockIP');
    $self->plugin('Bugzilla::Quantum::Plugin::BasicAuth');

    if ( $self->mode ne 'development' ) {
        $self->hook(
            after_static => sub {
                my ($c) = @_;
                $c->res->headers->cache_control('public, max-age=31536000');
            }
        );
    }

    my $r = $self->routes;
    Bugzilla::Quantum::CGI->load_all($r);
    Bugzilla::Quantum::CGI->load_one('bzapi_cgi', 'extensions/BzAPI/bin/rest.cgi');

    $r->any('/')->to('CGI#index_cgi');
    $r->any('/rest')->to('CGI#rest_cgi');
    $r->any('/rest.cgi/*PATH_INFP')->to('CGI#rest_cgi' => { PATH_INFO => '' });
    $r->any('/rest/*PATH_INFO')->to( 'CGI#rest_cgi' => { PATH_INFO => '' });
    $r->any('/bug/:id')->to('CGI#show_bug_cgi');
    $r->any('/extensions/BzAPI/bin/rest.cgi/*PATH_INFO')->to('CGI#bzapi_cgi');

    $r->get(
        '/__lbheartbeat__' => sub {
            my $c = shift;
            $c->reply->file( $c->app->home->child('__lbheartbeat__') );
        },
    );

    $r->get('/__heartbeat__')->to( 'CGI#heartbeat_cgi');
    $r->get('/robots.txt')->to( 'CGI#robots_cgi' );

    $r->any('/review')->to( 'CGI#page_cgi' => {'id' => 'splinter.html'});
    $r->any('/user_profile')->to( 'CGI#page_cgi' => {'id' => 'user_profile.html'});
    $r->any('/userprofile')->to( 'CGI#page_cgi' => {'id' => 'user_profile.html'});
    $r->any('/request_defer')->to( 'CGI#page_cgi' => {'id' => 'request_defer.html'});
    $r->any('/login')->to( 'CGI#index_cgi' => { 'GoAheadAndLogIn' => '1' });

    $r->any('/:new_bug' => [new_bug => qr{new[-_]bug}])->to( 'CGI#new_bug_cgi');

    my $ses_auth = $r->under(
        '/ses' => sub {
            my ($c) = @_;
            my $lc = Bugzilla->localconfig;

            return $c->basic_auth( 'SES', $lc->{ses_username}, $lc->{ses_password} );
        }
    );
    $ses_auth->any('/index.cgi')->to('SES#main');

    $r->any('/:REWRITE_itrequest' => [REWRITE_itrequest => qr{form[\.:]itrequest}])->to(
        'CGI#enter_bug_cgi' => { 'product' => 'Infrastructure & Operations', 'format' => 'itrequest' }
    );
    $r->any('/:REWRITE_mozlist' => [REWRITE_mozlist => qr{form[\.:]mozlist}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'mozlist'}
    );
    $r->any('/:REWRITE_poweredby' => [REWRITE_poweredby => qr{form[\.:]poweredby}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'poweredby'}
    );
    $r->any('/:REWRITE_presentation' => [REWRITE_presentation => qr{form[\.:]presentation}])->to(
        'cgi#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'presentation'}
    );
    $r->any('/:REWRITE_trademark' => [REWRITE_trademark => qr{form[\.:]trademark}])->to(
        'cgi#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'trademark'}
    );
    $r->any('/:REWRITE_recoverykey' => [REWRITE_recoverykey => qr{form[\.:]recoverykey}])->to(
        'cgi#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'recoverykey'}
    );
    $r->any('/:REWRITE_legal' => [REWRITE_legal => qr{form[\.:]legal}])->to(
        'CGI#enter_bug_cgi' => { 'product' => 'Legal', 'format' => 'legal' },
    );
    $r->any('/:REWRITE_recruiting' => [REWRITE_recruiting => qr{form[\.:]recruiting}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Recruiting', 'format' => 'recruiting'}
    );
    $r->any('/:REWRITE_intern' => [REWRITE_intern => qr{form[\.:]intern}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Recruiting', 'format' => 'intern'}
    );
    $r->any('/:REWRITE_mozpr' => [REWRITE_mozpr => qr{form[\.:]mozpr}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Mozilla PR', 'format' => 'mozpr' },
    );
    $r->any('/:REWRITE_reps_mentorship' => [REWRITE_reps_mentorship => qr{form[\.:]reps[\.:]mentorship}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Mozilla Reps','format' => 'mozreps' },
    );
    $r->any('/:REWRITE_reps_budget' => [REWRITE_reps_budget => qr{form[\.:]reps[\.:]budget}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Mozilla Reps','format' => 'remo-budget'}
    );
    $r->any('/:REWRITE_reps_swag' => [REWRITE_reps_swag => qr{form[\.:]reps[\.:]swag}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Mozilla Reps','format' => 'remo-swag'}
    );
    $r->any('/:REWRITE_reps_it' => [REWRITE_reps_it => qr{form[\.:]reps[\.:]it}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Mozilla Reps','format' => 'remo-it'}
    );
    $r->any('/:REWRITE_reps_payment' => [REWRITE_reps_payment => qr{form[\.:]reps[\.:]payment}])->to(
        'CGI#page_cgi' => {'id' => 'remo-form-payment.html'}
    );
    $r->any('/:REWRITE_csa_discourse' => [REWRITE_csa_discourse => qr{form[\.:]csa[\.:]discourse}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Infrastructure & Operations', 'format' => 'csa-discourse'}
    );
    $r->any('/:REWRITE_employee_incident' => [REWRITE_employee_incident => qr{form[\.:]employee[\.\-:]incident}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'mozilla.org', 'format' => 'employee-incident'}
    );
    $r->any('/:REWRITE_brownbag' => [REWRITE_brownbag => qr{form[\.:]brownbag}])->to(
        'CGI#https_air_mozilla_org_requests' => {}
    );
    $r->any('/:REWRITE_finance' => [REWRITE_finance => qr{form[\.:]finance}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Finance','format' => 'finance'}
    );
    $r->any('/:REWRITE_moz_project_review' => [REWRITE_moz_project_review => qr{form[\.:]moz[\.\-:]project[\.\-:]review}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'mozilla.org','format' => 'moz-project-review'}
    );
    $r->any('/:REWRITE_docs' => [REWRITE_docs => qr{form[\.:]docs?}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Developer Documentation','format' => 'doc'}
    );
    $r->any('/:REWRITE_mdn' => [REWRITE_mdn => qr{form[\.:]mdn?}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'mdn','product' => 'developer.mozilla.org'}
    );
    $r->any('/:REWRITE_swag_gear' => [REWRITE_swag_gear => qr{form[\.:](swag|gear)}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'swag','product' => 'Marketing'}
    );
    $r->any('/:REWRITE_costume' => [REWRITE_costume => qr{form[\.:]costume}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Marketing','format' => 'costume'}
    );
    $r->any('/:REWRITE_ipp' => [REWRITE_ipp => qr{form[\.:]ipp}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Internet Public Policy','format' => 'ipp'}
    );
    $r->any('/:REWRITE_creative' => [REWRITE_creative => qr{form[\.:]creative}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'creative','product' => 'Marketing'}
    );
    $r->any('/:REWRITE_user_engagement' => [REWRITE_user_engagement => qr{form[\.:]user[\.\-:]engagement}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'user-engagement','product' => 'Marketing'}
    );
    $r->any('/:REWRITE_dev_engagement_event' => [REWRITE_dev_engagement_event => qr{form[\.:]dev[\.\-:]engagement[\.\-\:]event}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Developer Engagement','format' => 'dev-engagement-event'}
    );
    $r->any('/:REWRITE_mobile_compat' => [REWRITE_mobile_compat => qr{form[\.:]mobile[\.\-:]compat}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Tech Evangelism','format' => 'mobile-compat'}
    );
    $r->any('/:REWRITE_web_bounty' => [REWRITE_web_bounty => qr{form[\.:]web[\.:]bounty}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'web-bounty','product' => 'mozilla.org'}
    );
    $r->any('/:REWRITE_automative' => [REWRITE_automative => qr{form[\.:]automative}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Testing','format' => 'automative'}
    );
    $r->any('/:REWRITE_comm_newsletter' => [REWRITE_comm_newsletter => qr{form[\.:]comm[\.:]newsletter}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'comm-newsletter','product' => 'Marketing'}
    );
    $r->any('/:REWRITE_screen_share_whitelist' => [REWRITE_screen_share_whitelist => qr{form[\.:]screen[\.:]share[\.:]whitelist}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'screen-share-whitelist','product' => 'Firefox'}
    );
    $r->any('/:REWRITE_data_compliance' => [REWRITE_data_compliance => qr{form[\.:]data[\.\-:]compliance}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Data Compliance','format' => 'data-compliance'}
    );
    $r->any('/:REWRITE_fsa_budget' => [REWRITE_fsa_budget => qr{form[\.:]fsa[\.:]budget}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'FSA','format' => 'fsa-budget'}
    );
    $r->any('/:REWRITE_triage_request' => [REWRITE_triage_request => qr{form[\.:]triage[\.\-]request}])->to(
        'CGI#page_cgi' => {'id' => 'triage_request.html'}
    );
    $r->any('/:REWRITE_crm_CRM' => [REWRITE_crm_CRM => qr{form[\.:](crm|CRM)}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'crm','product' => 'Marketing'}
    );
    $r->any('/:REWRITE_nda' => [REWRITE_nda => qr{form[\.:]nda}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Legal','format' => 'nda'}
    );
    $r->any('/:REWRITE_name_clearance' => [REWRITE_name_clearance => qr{form[\.:]name[\.:]clearance}])->to(
        'CGI#enter_bug_cgi' => {'format' => 'name-clearance','product' => 'Legal'}
    );
    $r->any('/:REWRITE_shield_studies' => [REWRITE_shield_studies => qr{form[\.:]shield[\.:]studies}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Shield','format' => 'shield-studies'}
    );
    $r->any('/:REWRITE_client_bounty' => [REWRITE_client_bounty => qr{form[\.:]client[\.:]bounty}])->to(
        'CGI#enter_bug_cgi' => {'product' => 'Firefox','format' => 'client-bounty'}
    );

}

1;
