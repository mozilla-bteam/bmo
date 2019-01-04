#!/usr/bin/env perl
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Terry Weissman.
# Portions created by Terry Weissman are
# Copyright (C) 2000 Terry Weissman. All
# Rights Reserved.
#
# Contributor(s): Terry Weissman <terry@mozilla.org>
# Contributor(s): Gervase Markham <gerv@gerv.net>

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Keyword;

Bugzilla->login();

my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

# Run queries against the shadow DB.
Bugzilla->switch_to_shadow_db;

# Hide bug counts for security keywords from users who aren't a member of the
# security group
my $can_see_security = Bugzilla->user->in_group('core-security-release');
my $keywords         = Bugzilla::Keyword->get_all_with_bug_count();
foreach my $keyword (@$keywords) {
  $keyword->{'bug_count'} = 0
    if $keyword->name =~ /^(?:sec|csec|wsec|opsec)-/ && !$can_see_security;
}

$vars->{'keywords'}        = $keywords;
$vars->{'caneditkeywords'} = Bugzilla->user->in_group("editkeywords");

print Bugzilla->cgi->header();
$template->process("reports/keywords.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
