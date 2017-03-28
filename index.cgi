#!/usr/bin/perl -T
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
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Update;
use Digest::MD5 qw(md5_hex);
use List::MoreUtils qw(any);

# Check whether or not the user is logged in
my $user = Bugzilla->login(LOGIN_OPTIONAL);
my $cgi = Bugzilla->cgi;
my $vars = {};

# And log out the user if requested. We do this first so that nothing
# else accidentally relies on the current login.
if ($cgi->param('logout')) {
    Bugzilla->logout();
    $user = Bugzilla->user;
    $vars->{'message'} = "logged_out";
    # Make sure that templates or other code doesn't get confused about this.
    $cgi->delete('logout');
}

my @cache_control = (
    $user->id ? 'private' : 'public',
    sprintf('max-age=%d', time() + MAX_TOKEN_AGE * 86400),
);

my $weak_etag = q{W/"} . md5_hex(Bugzilla->user->id, Bugzilla->params->{bugzilla_version}) . q{"};

my $if_none_match = $cgi->http('If-None-Match');
if ($if_none_match && any { $_ eq $weak_etag } split(/,\s*/, $if_none_match)) {
    print $cgi->header(-status => '304 Not Modified', -ETag => $weak_etag);
}
else {
    my $template = Bugzilla->template;
    $cgi->content_security_policy(script_src  => ['self']);

    # Return the appropriate HTTP response headers.
    print $cgi->header(-Cache_Control => join(', ', @cache_control), -ETag => $weak_etag);

    if ($user->in_group('admin')) {
        # If 'urlbase' is not set, display the Welcome page.
        unless (Bugzilla->params->{'urlbase'}) {
            $template->process('welcome-admin.html.tmpl')
            || ThrowTemplateError($template->error());
            exit;
        }
        # Inform the administrator about new releases, if any.
        $vars->{'release'} = Bugzilla::Update::get_notifications();
    }

    # Generate and return the UI (HTML page) from the appropriate template.
    $template->process("index.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
}
