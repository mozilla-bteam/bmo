#!/usr/bin/env perl
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
use Bugzilla::Hook;
use Bugzilla::Teams qw(team_names);
use Bugzilla::Token;
use Bugzilla::User;
use Bugzilla::Util;

use List::Util qw(any);

my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars     = {};

# There is only one section about components in the documentation,
# so all actions point to the same page.
$vars->{'doc_section'} = 'components.html';

#
# Often used variables
#
my $user              = Bugzilla->login(LOGIN_REQUIRED);
my $product_name      = trim($cgi->param('product')   || '');
my $comp_name         = trim($cgi->param('component') || '');
my $action            = trim($cgi->param('action')    || '');
my $showbugcounts     = (defined $cgi->param('showbugcounts'));
my $token             = $cgi->param('token');
my $editcomponents    = $user->in_group('editcomponents');
my $edittriageowners  = $user->in_group('edittriageowners');
my $editable_products = $user->get_products_by_permission('editcomponents');

print $cgi->header();

#
# Preliminary permission checks:
#

$editcomponents
  || scalar @{$editable_products}
  || $edittriageowners
  || ThrowUserError("auth_failure",
  {group => "editcomponents", action => "edit", object => "components"});

#
# product = '' -> Show nice list of products
#

unless ($product_name) {
  my $selectable_products = $user->get_selectable_products;

  # If the user has editcomponents privs for some products only,
  # we have to restrict the list of products to display.
  unless ($editcomponents || $edittriageowners) {
    $selectable_products = $editable_products;
  }

  $vars->{'products'}      = $selectable_products;
  $vars->{'showbugcounts'} = $showbugcounts;

  $template->process("admin/components/select-product.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

my $product = $user->check_can_admin_product($product_name);

# If user can edit the component based on product specific permissions
# then set edit_components true
$editcomponents
  = $editcomponents || any { $_->id == $product->id } @{$editable_products};

# Pass in commonly needed values to the templates
$vars->{editcomponents}   = $editcomponents;
$vars->{edittriageowners} = $edittriageowners;

#
# action='' -> Show nice list of components
#

unless ($action) {
  $vars->{'showbugcounts'} = $showbugcounts;
  $vars->{'product'}       = $product;
  $template->process("admin/components/list.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='add' -> present form for parameters for new component
#
# (next action will be 'new')
#

if ($action eq 'add' && $editcomponents) {
  $vars->{'token'}      = issue_session_token('add_component');
  $vars->{'product'}    = $product;
  $vars->{'team_names'} = team_names();
  $template->process("admin/components/create.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='new' -> add component entered in the 'action=add' screen
#

if ($action eq 'new' && $editcomponents) {
  check_token_data($token, 'add_component');

  # Do the user matching
  Bugzilla::User::match_field({
    'initialowner'     => {'type' => 'single'},
    'initialqacontact' => {'type' => 'single'},
    'triage_owner'     => {'type' => 'single'},
    'initialcc'        => {'type' => 'multi'},
  });

  my $params = {
    name                     => $comp_name,
    product                  => $product,
    description              => trim($cgi->param('description')      || ''),
    initialowner             => trim($cgi->param('initialowner')     || ''),
    initialqacontact         => trim($cgi->param('initialqacontact') || ''),
    initial_cc               => [$cgi->param('initialcc')],
    triage_owner_id          => trim($cgi->param('triage_owner') || ''),
    team_name                => trim($cgi->param('team_name')    || ''),
    default_bug_type         => scalar $cgi->param('default_bug_type'),
    bug_description_template => trim($cgi->param('bug_description_template') || ''),

    # XXX We should not be creating series for products that we
    # didn't create series for.
    create_series => 1,
  };


  Bugzilla::Hook::process('editcomponents_before_create', {params => $params});

  my $component = Bugzilla::Component->create($params);

  $vars->{'message'} = 'component_created';
  $vars->{'comp'}    = $component;
  $vars->{'product'} = $product;
  delete_token($token);

  $template->process("admin/components/list.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='del' -> ask if user really wants to delete
#
# (next action would be 'delete')
#

if ($action eq 'del'  && $editcomponents) {
  $vars->{'token'} = issue_session_token('delete_component');
  $vars->{'comp'}
    = Bugzilla::Component->check({product => $product, name => $comp_name});
  $vars->{'product'} = $product;

  $template->process("admin/components/confirm-delete.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='delete' -> really delete the component
#

if ($action eq 'delete' && $editcomponents) {
  check_token_data($token, 'delete_component');
  my $component
    = Bugzilla::Component->check({product => $product, name => $comp_name});

  $component->remove_from_db;

  $vars->{'message'}                = 'component_deleted';
  $vars->{'comp'}                   = $component;
  $vars->{'product'}                = $product;
  $vars->{'no_edit_component_link'} = 1;
  delete_token($token);

  $template->process("admin/components/list.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='edit' -> present the edit component form
#
# (next action would be 'update')
#

if ($action eq 'edit') {
  $vars->{'token'} = issue_session_token('edit_component');
  my $component
    = Bugzilla::Component->check({product => $product, name => $comp_name});
  $vars->{'comp'} = $component;

  $vars->{'initial_cc_names'}
    = join(', ', map($_->login, @{$component->initial_cc}));

  $vars->{'product'}    = $product;
  $vars->{'team_names'} = team_names();

  $template->process("admin/components/edit.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

#
# action='update' -> update the component
#

if ($action eq 'update') {
  check_token_data($token, 'edit_component');

  # Do the user matching
  Bugzilla::User::match_field({
    'initialowner'     => {'type' => 'single'},
    'initialqacontact' => {'type' => 'single'},
    'triage_owner'     => {'type' => 'single'},
    'initialcc'        => {'type' => 'multi'},
  });

  my $comp_old_name = trim($cgi->param('componentold') || '');

  my $component
    = Bugzilla::Component->check({product => $product, name => $comp_old_name});

  if ($editcomponents) {
    my $default_bug_type   = trim($cgi->param('default_bug_type') || '');
    my $default_assignee   = trim($cgi->param('initialowner')     || '');
    my $default_qa_contact = trim($cgi->param('initialqacontact') || '');
    my $description        = trim($cgi->param('description')      || '');
    my $team_name          = trim($cgi->param('team_name')        || '');
    my @initial_cc         = $cgi->param('initialcc');
    my $isactive           = $cgi->param('isactive');
    my $bug_desc_template  = $cgi->param('bug_description_template'),

    $component->set_name($comp_name);
    $component->set_description($description);
    $component->set_default_bug_type($default_bug_type);
    $component->set_default_assignee($default_assignee);
    $component->set_default_qa_contact($default_qa_contact);
    $component->set_team_name($team_name);
    $component->set_cc_list(\@initial_cc);
    $component->set_is_active($isactive);
    $component->set_bug_description_template($bug_desc_template);
  }

  if ($edittriageowners) {
    my $triage_owner = trim($cgi->param('triage_owner') || '');
    $component->set_triage_owner($triage_owner);
  }

  Bugzilla::Hook::process('editcomponents_before_update',
    {component => $component});

  my $changes = $component->update();

  $vars->{'message'} = 'component_updated';
  $vars->{'comp'}    = $component;
  $vars->{'product'} = $product;
  $vars->{'changes'} = $changes;
  delete_token($token);

  $template->process("admin/components/list.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
  exit;
}

# No valid action found
ThrowUserError('unknown_action', {action => $action});
