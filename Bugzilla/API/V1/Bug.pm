# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::V1::Bug;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Comment;
use Bugzilla::Comment::TagWeights;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::API::V1::Constants;
use Bugzilla::API::V1::Util
  qw(extract_flags filter filter_wants validate translate);
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Util qw(trim detaint_natural remote_ip);
use Bugzilla::Version;
use Bugzilla::Milestone;
use Bugzilla::Status;
use Bugzilla::Token qw(issue_hash_token);
use Bugzilla::Search;
use Bugzilla::Product;
use Bugzilla::FlagType;
use Bugzilla::Search::Quicksearch;

use List::Util qw(max);
use List::MoreUtils qw(any uniq);
use Mojo::JSON;
use Storable qw(dclone);
use Types::Standard -all;
use Type::Utils;

#############
# Constants #
#############

use constant PRODUCT_SPECIFIC_FIELDS => qw(version target_milestone component);

sub DATE_FIELDS {
  my $fields = {
    comments => ['new_since'],
    create   => [],
    history  => ['new_since'],
    search   => ['last_change_time', 'creation_time'],
    update   => []
  };

  # Add date related custom fields
  foreach my $field (Bugzilla->active_custom_fields({skip_extensions => 1})) {
    next
      unless ($field->type == FIELD_TYPE_DATETIME
      || $field->type == FIELD_TYPE_DATE);
    push @{$fields->{create}}, $field->name;
    push @{$fields->{update}}, $field->name;
  }

  return $fields;
}

use constant BASE64_FIELDS => {add_attachment => ['data'],};

use constant ATTACHMENT_MAPPED_SETTERS =>
  {file_name => 'filename', summary => 'description',};

use constant ATTACHMENT_MAPPED_RETURNS => {
  description => 'summary',
  ispatch     => 'is_patch',
  isprivate   => 'is_private',
  isobsolete  => 'is_obsolete',
  filename    => 'file_name',
  mimetype    => 'content_type',
};

our %api_field_types = (
  %{{map { $_ => 'double' } Bugzilla::Bug::NUMERIC_COLUMNS()}},
  %{{map { $_ => 'dateTime' } Bugzilla::Bug::DATE_COLUMNS()}},
);

our %api_field_names = reverse %{Bugzilla::Bug::FIELD_MAP()};

# This doesn't normally belong in FIELD_MAP, but we do want to translate
# "bug_group" back into "groups".
$api_field_names{'bug_group'} = 'groups';

###########
# Methods #
###########

sub setup_routes {
  my ($class, $r) = @_;
  $r->get('/rest/bug')->to('V1::Bug#search');
  $r->post('/rest/bug')->to('V1::Bug#create');
  $r->get('/rest/possible_duplicates')->to('V1::Bug#possible_duplicates');
  $r->get('/rest/bug/:id')->to('V1::Bug#get');
  $r->put('/rest/bug/:id')->to('V1::Bug#update');
  $r->get('/rest/bug/:id/comment')->to('V1::Bug#comments');
  $r->post('/rest/bug/:id/comment')->to('V1::Bug#add_comment');
  $r->get('/rest/bug/comment/:comment_id')->to('V1::Bug#comments');
  $r->get('/rest/bug/comment/tags/:query')->to('V1::Bug#search_comment_tags');
  $r->put('/rest/bug/comment/:comment_id/tags')
    ->to('V1::Bug#update_comment_tags');
  $r->post('/rest/bug/comment/render')->to('V1::Bug#render_comment');
  $r->get('/rest/bug/:id/history')->to('V1::Bug#history');
  $r->get('/rest/bug/:id/attachment')->to('V1::Bug#attachments');
  $r->post('/rest/bug/:id/attachment')->to('V1::Bug#add_attachment');
  $r->get('/rest/bug/attachment/:attach_id')->to('V1::Bug#attachments');
  $r->put('/rest/bug/attachment/:attach_id')->to('V1::Bug#update_attachment');
  $r->get('/rest/field/bug')->to('V1::Bug#fields');
  $r->get('/rest/field/bug/:name')->to('V1::Bug#fields');
  $r->get('/rest/bug/field/:field/values')->to('V1::Bug#legal_values');
  $r->get('/rest/bug/field/:field/:product_id/values')
    ->to('V1::Bug#legal_values');
  $r->get('/rest/flag_types/:product')->to('V1::Bug#flag_types');
  $r->get('/rest/flag_types/:product/:component')->to('V1::Bug#flag_types');
}

sub fields {
  my ($self) = @_;
  my $params = $self->param->to_hash;
  my $fields = [];

  Bugzilla->switch_to_shadow_db();

  if (my $names = $params->{names}) {
    foreach my $field (@{$names}) {
      push @{$fields}, Bugzilla::Field->check($field);
    }
  }
  else {
    $fields = Bugzilla->fields({obsolete => 0});
  }

  my @fields_out;
  foreach my $field (@{$fields}) {
    my $visibility_field
      = $field->visibility_field ? $field->visibility_field->name : undef;
    my $vis_values  = $field->visibility_values;
    my $value_field = $field->value_field ? $field->value_field->name : undef;

    my (@values, $has_values);
    if (
      ($field->is_select and $field->name ne 'product') or any { $_ eq $field->name },
      PRODUCT_SPECIFIC_FIELDS or $field->name eq 'keywords'
      )
    {
      $has_values = 1;
      $values     = $self->_legal_field_values({field => $field});
    }

    if (any { $_ eq $field->name }, PRODUCT_SPECIFIC_FIELDS) {
      $value_field = 'product';
    }

    my %field_data = (
      id                => $self->type('int',     $field->id),
      type              => $self->type('int',     $field->type),
      is_custom         => $self->type('boolean', $field->custom),
      name              => $self->type('string',  $field->name),
      display_name      => $self->type('string',  $field->description),
      is_mandatory      => $self->type('boolean', $field->is_mandatory),
      is_on_bug_entry   => $self->type('boolean', $field->enter_bug),
      visibility_field  => $self->type('string',  $visibility_field),
      visibility_values => [map { $self->type('string', $_->name) } @{$vis_values}],

    );
    if ($has_values) {
      $field_data{value_field} = $self->type('string', $value_field);
      $field_data{values}      = $values;
    }
    push @fields_out, filter($params, \%field_data);
  }

  return $self->render(json => {fields => \@fields_out});
}

sub _legal_field_values {
  my ($self)     = @_;
  my $params     = $self->param->to_hash;
  my $field      = $params->{field};
  my $field_name = $field->name;
  my $user       = Bugzilla->user;

  my @result;
  if (any { $_ eq $field_name }, PRODUCT_SPECIFIC_FIELDS) {
    my @list;
    if ($field_name eq 'version') {
      @list = Bugzilla::Version->get_all;
    }
    elsif ($field_name eq 'component') {
      @list = Bugzilla::Component->get_all;
    }
    else {
      @list = Bugzilla::Milestone->get_all;
    }

    foreach my $value (@list) {
      my $sortkey = $field_name eq 'target_milestone' ? $value->sortkey : 0;

      # XXX This is very slow for large numbers of values.
      my $product_name = $value->product->name;
      if ($user->can_see_product($product_name)) {
        push(
          @result,
          {
            name              => $self->type('string', $value->name),
            sort_key          => $self->type('int',    $sortkey),
            sortkey           => $self->type('int',    $sortkey),       # deprecated
            visibility_values => [$self->type('string', $product_name)],
          }
        );
      }
    }
  }

  elsif ($field_name eq 'bug_status') {
    my @status_all = Bugzilla::Status->get_all;
    foreach my $status (@status_all) {
      my @can_change_to;
      foreach my $change_to (@{$status->can_change_to}) {

        # There's no need to note that a status can transition
        # to itself.
        next if $change_to->id == $status->id;
        my %change_to_hash = (
          name             => $self->type('string', $change_to->name),
          comment_required =>
            $self->type('boolean', $change_to->comment_required_on_change_from($status)),
        );
        push @can_change_to, \%change_to_hash;
      }

      push @result, {
        name              => $self->type('string',  $status->name),
        is_open           => $self->type('boolean', $status->is_open),
        sort_key          => $self->type('int',     $status->sortkey),
        sortkey           => $self->type('int',     $status->sortkey),    # deprecated
        can_change_to     => \@can_change_to,
        visibility_values => [],
      };
    }
  }

  elsif ($field_name eq 'keywords') {
    my @legal_keywords = Bugzilla::Keyword->get_all;
    foreach my $value (@legal_keywords) {
      next unless $value->is_active;
      push @result,
        {
        name        => $self->type('string', $value->name),
        description => $self->type('string', $value->description),
        };
    }
  }
  else {
    my @values = Bugzilla::Field::Choice->type($field)->get_all();
    foreach my $value (@values) {
      my $vis_val = $value->visibility_value;
      push @result, {
        name              => $self->type('string', $value->name),
        sort_key          => $self->type('int',    $value->sortkey),
        sortkey           => $self->type('int',    $value->sortkey),    # deprecated
        visibility_values =>
          [defined $vis_val ? $self->type('string', $vis_val->name) : ()],
      };
    }
  }

  return $self->render(json => \@result);
}

sub comments {
  my ($self) = @_;
  my $params = $self->param->to_hash;

  if (!(defined $params->{ids} || defined $params->{comment_ids})) {
    ThrowCodeError('params_required',
      {function => 'Bug.comments', params => ['ids', 'comment_ids']});
  }

  my $bug_ids      = $params->{ids}         || [];
  my $comment_ids  = $params->{comment_ids} || [];
  my $skip_private = $params->{skip_private} ? 1 : 0;

  my $dbh  = Bugzilla->switch_to_shadow_db();
  my $user = Bugzilla->user;

  unless (Bugzilla->user->id) {
    Bugzilla->check_rate_limit("get_comments", remote_ip());
  }

  if ($skip_private) {

    # Cache permissions for bugs. This highly reduces the number of calls to the DB.
    # visible_bugs() is only able to handle bug IDs, so we have to skip aliases.
    my @int = grep { $_ =~ /^\d+$/ } @$bug_ids;
    $user->visible_bugs(\@int);
  }

  my %bugs;
  foreach my $bug_id (@$bug_ids) {
    my $bug;

    if ($skip_private) {
      $bug = Bugzilla::Bug->new({id => $bug_id, cache => 1});
      next if $bug->error || !$user->can_see_bug($bug->id);
    }
    else {
      $bug = Bugzilla::Bug->check($bug_id);
    }

    # We want the API to always return comments in the same order.

    my $comments
      = $bug->comments({order => 'oldest_to_newest', after => $params->{new_since}
      });
    my @result;
    foreach my $comment (@$comments) {
      next if $comment->is_private && !$user->is_insider;
      push(@result, $self->_translate_comment($comment, $params));
    }
    $bugs{$bug->id}{'comments'} = \@result;
  }

  my %comments;
  if (scalar @$comment_ids) {
    my @ids          = map { trim($_) } @$comment_ids;
    my $comment_data = Bugzilla::Comment->new_from_list(\@ids);

    # See if we were passed any invalid comment ids.
    my %got_ids = map { $_->id => 1 } @$comment_data;
    foreach my $comment_id (@ids) {
      if (!$got_ids{$comment_id}) {
        ThrowUserError('comment_id_invalid', {id => $comment_id});
      }
    }

    # Now make sure that we can see all the associated bugs.
    my %got_bug_ids = map { $_->bug_id => 1 } @$comment_data;
    Bugzilla::Bug->check($_) foreach (keys %got_bug_ids);

    foreach my $comment (@$comment_data) {
      if ($comment->is_private && !$user->is_insider) {
        ThrowUserError('comment_is_private', {id => $comment->id});
      }
      $comments{$comment->id} = $self->_translate_comment($comment, $params);
    }
  }

  return {bugs => \%bugs, comments => \%comments};
}

sub render_comment {
  my ($self, $params) = @_;

  unless (defined $params->{text}) {
    ThrowCodeError('params_required',
      {function => 'Bug.render_comment', params => ['text']});
  }

  Bugzilla->switch_to_shadow_db();
  my $bug = $params->{id} ? Bugzilla::Bug->check($params->{id}) : undef;

  my $html
    = Bugzilla->params->{use_markdown}
    ? Bugzilla->markdown->render_html($params->{text}, $bug)
    : Bugzilla::Template::quoteUrls($params->{text}, $bug);

  return {html => $html};
}

# Helper for Bug.comments
sub _translate_comment {
  my ($self, $comment, $filters, $types, $prefix) = @_;
  my $attach_id = $comment->is_about_attachment ? $comment->extra_data : undef;

  my $comment_hash = {
    id            => $self->type('int',      $comment->id),
    bug_id        => $self->type('int',      $comment->bug_id),
    creator       => $self->type('email',    $comment->author->login),
    author        => $self->type('email',    $comment->author->login),
    time          => $self->type('dateTime', $comment->creation_ts),
    creation_time => $self->type('dateTime', $comment->creation_ts),
    is_private    => $self->type('boolean',  $comment->is_private),
    text          => $self->type('string',   $comment->body_full),
    raw_text      => $self->type('string',   $comment->body),
    attachment_id => $self->type('int',      $attach_id),
    count         => $self->type('int',      $comment->count),
  };

  # Don't load comment tags unless enabled
  if (Bugzilla->params->{'comment_taggers_group'}) {
    $comment_hash->{tags} = [map { $self->type('string', $_) } @{$comment->tags}];
  }

  return filter($filters, $comment_hash, $types, $prefix);
}

sub get {
  my ($self, $params) = validate(@_, 'ids');

  unless (Bugzilla->user->id) {
    Bugzilla->check_rate_limit("get_bug", remote_ip());
  }
  Bugzilla->switch_to_shadow_db() unless Bugzilla->user->id;

  my $ids = $params->{ids};
  (defined $ids && scalar @$ids)
    || ThrowCodeError('param_required', {param => 'ids'});

  my (@bugs, @faults, @hashes);

  # Cache permissions for bugs. This highly reduces the number of calls to the DB.
  # visible_bugs() is only able to handle bug IDs, so we have to skip aliases.
  my @int = grep { $_ =~ /^\d+$/ } @$ids;
  Bugzilla->user->visible_bugs(\@int);

  foreach my $bug_id (@$ids) {
    my $bug;
    if ($params->{permissive}) {
      eval { $bug = Bugzilla::Bug->check($bug_id); };
      if ($@) {
        push(@faults,
          {id => $bug_id, faultString => $@->faultstring, faultCode => $@->faultcode,});
        undef $@;
        next;
      }
    }
    else {
      $bug = Bugzilla::Bug->check($bug_id);
    }
    push(@bugs,   $bug);
    push(@hashes, $self->_bug_to_hash($bug, $params));
  }

  # Set the ETag before inserting the update tokens
  # since the tokens will always be unique even if
  # the data has not changed.
  $self->bz_etag(\@hashes);

  $self->_add_update_tokens($params, \@bugs, \@hashes);

  if (Bugzilla->user->id) {
    foreach my $bug (@bugs) {
      Bugzilla->log_user_request($bug->id, undef, 'bug-get');
    }
  }
  return {bugs => \@hashes, faults => \@faults};
}

# this is a function that gets bug activity for list of bug ids
# it can be called as the following:
# $call = $rpc->call( 'Bug.history', { ids => [1,2] });
sub history {
  my ($self, $params) = validate(@_, 'ids');

  Bugzilla->switch_to_shadow_db();

  my $ids = $params->{ids};
  defined $ids || ThrowCodeError('param_required', {param => 'ids'});

  my $user         = Bugzilla->user;
  my $skip_private = $params->{skip_private} ? 1 : 0;

  if ($skip_private) {

    # Cache permissions for bugs. This highly reduces the number of calls to the DB.
    # visible_bugs() is only able to handle bug IDs, so we have to skip aliases.
    my @int = grep { $_ =~ /^\d+$/ } @$ids;
    $user->visible_bugs(\@int);
  }

  my @return;
  foreach my $bug_id (@$ids) {
    my %item;
    my $bug;

    if ($skip_private) {
      $bug = Bugzilla::Bug->new({id => $bug_id, cache => 1});
      next if $bug->error || !$user->can_see_bug($bug->id);
    }
    else {
      $bug = Bugzilla::Bug->check($bug_id);
    }

    $bug_id = $bug->id;
    $item{id} = $self->type('int', $bug_id);

    my ($activity)
      = Bugzilla::Bug::GetBugActivity($bug_id, undef, $params->{new_since}, 1);

    my @history;
    foreach my $changeset (@$activity) {
      push(@history, $self->_changeset_to_hash($changeset, $params));
    }

    $item{history} = \@history;

    # alias is returned in case users passes a mixture of ids and aliases
    # then they get to know which bug activity relates to which value
    # they passed
    if (Bugzilla->params->{'usebugaliases'}) {
      $item{alias} = $self->type('string', $bug->alias);
    }
    else {
      # For API reasons, we always want the value to appear, we just
      # don't want it to have a value if aliases are turned off.
      $item{alias} = undef;
    }

    push(@return, \%item);
  }

  return {bugs => \@return};
}

sub search {
  my ($self, $params) = @_;
  my $user = Bugzilla->user;
  my $dbh  = Bugzilla->dbh;

  Bugzilla->switch_to_shadow_db();

  my $match_params = dclone($params);
  delete $match_params->{include_fields};
  delete $match_params->{exclude_fields};

  # Determine whether this is a quicksearch query
  if (exists $match_params->{quicksearch}) {
    my $quicksearch = quicksearch($match_params->{'quicksearch'});
    my $cgi         = Bugzilla::CGI->new($quicksearch);
    $match_params = $cgi->Vars;
  }

  if (defined($match_params->{offset}) and !defined($match_params->{limit})) {
    ThrowCodeError('param_required',
      {param => 'limit', function => 'Bug.search()'});
  }

  my $max_results = Bugzilla->params->{max_search_results};
  unless (defined $match_params->{limit} && $match_params->{limit} == 0) {
    if (!defined $match_params->{limit} || $match_params->{limit} > $max_results) {
      $match_params->{limit} = $max_results;
    }
  }
  else {
    delete $match_params->{limit};
    delete $match_params->{offset};
  }

  # Allow to search only in bug description (initial comment)
  if (defined $match_params->{description}) {
    $match_params->{longdesc}         = delete $match_params->{description};
    $match_params->{longdesc_initial} = 1;
  }

  $match_params = Bugzilla::Bug::map_fields($match_params);

  my %options = (fields => ['bug_id']);

  # Find the highest custom field id
  my @field_ids     = grep(/^f(\d+)$/, keys %$match_params);
  my $last_field_id = @field_ids ? max @field_ids + 1 : 1;

  # Do special search types for certain fields.
  if (my $change_when = delete $match_params->{'delta_ts'}) {
    $match_params->{"f${last_field_id}"} = 'delta_ts';
    $match_params->{"o${last_field_id}"} = 'greaterthaneq';
    $match_params->{"v${last_field_id}"} = $change_when;
    $last_field_id++;
  }
  if (my $creation_when = delete $match_params->{'creation_ts'}) {
    $match_params->{"f${last_field_id}"} = 'creation_ts';
    $match_params->{"o${last_field_id}"} = 'greaterthaneq';
    $match_params->{"v${last_field_id}"} = $creation_when;
    $last_field_id++;
  }

  # Some fields require a search type such as short desc, keywords, etc.
  foreach my $param (qw(short_desc longdesc status_whiteboard bug_file_loc)) {
    if (defined $match_params->{$param}
      && !defined $match_params->{$param . '_type'})
    {
      $match_params->{$param . '_type'} = 'allwordssubstr';
    }
  }
  if (defined $match_params->{'keywords'}
    && !defined $match_params->{'keywords_type'})
  {
    $match_params->{'keywords_type'} = 'allwords';
  }

  # Backwards compatibility with old method regarding role search
  $match_params->{'reporter'} = delete $match_params->{'creator'}
    if $match_params->{'creator'};
  foreach my $role (qw(assigned_to reporter qa_contact triage_owner commenter cc))
  {
    next if !exists $match_params->{$role};
    my $value = delete $match_params->{$role};
    $match_params->{"f${last_field_id}"} = $role;
    $match_params->{"o${last_field_id}"} = "anywordssubstr";
    $match_params->{"v${last_field_id}"}
      = ref $value ? join(" ", @{$value}) : $value;
    $last_field_id++;
  }

  # If no other parameters have been passed other than limit and offset
  # then we throw error if system is configured to do so.
  if ( !grep(!/^(limit|offset)$/, keys %$match_params)
    && !Bugzilla->params->{search_allow_no_criteria})
  {
    ThrowUserError('buglist_parameters_required');
  }

  # Allow the use of order shortcuts similar to web UI
  if ($match_params->{order}) {

    # Convert the value of the "order" form field into a list of columns
    # by which to sort the results.
    my %order_types = (
      "Bug Number"   => ["bug_id"],
      "Importance"   => ["priority",    "bug_severity"],
      "Assignee"     => ["assigned_to", "bug_status", "priority", "bug_id"],
      "Last Updated" =>
        ["changeddate", "bug_status", "priority", "assigned_to", "bug_id"],
    );
    if ($order_types{$match_params->{order}}) {
      $options{order} = $order_types{$match_params->{order}};
    }
    else {
      $options{order} = [split(/\s*,\s*/, $match_params->{order})];
    }
  }

  $options{params} = $match_params;

  my $search = new Bugzilla::Search(%options);
  my ($data) = $search->data;

  # BMO if the caller only wants the count, that's all we need to return
  if ($params->{count_only}) {
    if (Bugzilla->usage_mode == USAGE_MODE_XMLRPC) {
      return $data;
    }
    else {
      return {bug_count => $self->type('int', $data)};
    }
  }

  if (!scalar @$data) {
    return {bugs => []};
  }

# Search.pm won't return bugs that the user shouldn't see so no filtering is needed.
  my @bug_ids = map { $_->[0] } @$data;
  my %bug_objects
    = map { $_->id => $_ } @{Bugzilla::Bug->new_from_list(\@bug_ids)};
  my @bugs = map { $bug_objects{$_} } @bug_ids;
  @bugs = map { $self->_bug_to_hash($_, $params) } @bugs;

  # BzAPI
  Bugzilla->request_cache->{bzapi_search_bugs}
    = [map { $bug_objects{$_} } @bug_ids];

  return {bugs => \@bugs};
}

sub possible_duplicates {
  my ($self, $params) = validate(@_, 'product');
  my $user = Bugzilla->user;

  Bugzilla->switch_to_shadow_db();

  state $params_type = Dict [
    id                 => Optional [Int],
    product            => Optional [ArrayRef [Str]],
    limit              => Optional [Int],
    summary            => Optional [Str],
    include_fields     => Optional [ArrayRef [Str]],
    Bugzilla_api_token => Optional [Str]
  ];

  ThrowCodeError('param_invalid',
    {function => 'Bug.possible_duplicates', param => 'A param'})
    if !$params_type->check($params);

  my $summary;
  if ($params->{id}) {
    my $bug = Bugzilla::Bug->check({id => $params->{id}, cache => 1});
    $summary = $bug->short_desc;
  }
  elsif ($params->{summary}) {
    $summary = $params->{summary};
  }
  else {
    ThrowCodeError('param_required',
      {function => 'Bug.possible_duplicates', param => 'id or summary'});
  }

  my @products;
  foreach my $name (@{$params->{'product'} || []}) {
    my $object = $user->can_enter_product($name, THROW_ERROR);
    push(@products, $object);
  }

  my $possible_dupes
    = Bugzilla::Bug->possible_duplicates({
    summary => $summary, products => \@products, limit => $params->{limit}
    });

  # If a bug id was used, remove the bug with the same id from the list.
  if ($params->{id}) {
    @$possible_dupes = grep { $_->id != $params->{id} } @$possible_dupes;
  }

  my @hashes = map { $self->_bug_to_hash($_, $params) } @$possible_dupes;
  $self->_add_update_tokens($params, $possible_dupes, \@hashes);
  return {bugs => \@hashes};
}

sub update {
  my ($self, $params) = validate(@_, 'ids');

  # BMO: Don't allow updating of bugs if disabled
  if (Bugzilla->params->{disable_bug_updates}) {
    ThrowErrorPage(
      'bug/process/updates-disabled.html.tmpl',
      'Bug updates are currently disabled.'
    );
  }

  my $user = Bugzilla->login(LOGIN_REQUIRED);
  my $dbh  = Bugzilla->dbh;

  # We skip certain fields because their set_ methods actually use
  # the external names instead of the internal names.
  $params = Bugzilla::Bug::map_fields($params,
    {summary => 1, platform => 1, severity => 1, type => 1, url => 1});

  my $ids = delete $params->{ids};
  defined $ids || ThrowCodeError('param_required', {param => 'ids'});

  my @bugs = map { Bugzilla::Bug->check($_) } @$ids;

  my %values = %$params;
  $values{other_bugs} = \@bugs;

  if (exists $values{comment} and exists $values{comment}{comment}) {
    $values{comment}{body} = delete $values{comment}{comment};
  }

  # Prevent bugs that could be triggered by specifying fields that
  # have valid "set_" functions in Bugzilla::Bug, but shouldn't be
  # called using those field names.
  delete $values{dependencies};

  my $flags = delete $values{flags};

  foreach my $bug (@bugs) {
    if (!$user->can_edit_product($bug->product_obj->id)) {
      ThrowUserError("product_edit_denied", {product => $bug->product});
    }

    $bug->set_all(\%values);
    if ($flags) {
      my ($old_flags, $new_flags) = extract_flags($flags, $bug);
      $bug->set_flags($old_flags, $new_flags);
    }
  }

  my %all_changes;
  $dbh->bz_start_transaction();
  foreach my $bug (@bugs) {
    $all_changes{$bug->id} = $bug->update();
  }
  $dbh->bz_commit_transaction();

  foreach my $bug (@bugs) {
    $bug->send_changes($all_changes{$bug->id});
  }

  my @result;
  foreach my $bug (@bugs) {
    my %hash = (
      id               => $self->type('int',      $bug->id),
      last_change_time => $self->type('dateTime', $bug->delta_ts),
      changes          => {},
    );

    # alias is returned in case users pass a mixture of ids and aliases,
    # so that they can know which set of changes relates to which value
    # they passed.
    if (Bugzilla->params->{'usebugaliases'}) {
      $hash{alias} = $self->type('string', $bug->alias);
    }
    else {
      # For API reasons, we always want the alias field to appear, we
      # just don't want it to have a value if aliases are turned off.
      $hash{alias} = $self->type('string', '');
    }

    my %changes = %{$all_changes{$bug->id}};
    foreach my $field (keys %changes) {
      my $change    = $changes{$field};
      my $api_field = $api_field_names{$field} || $field;

      # We normalize undef to an empty string, so that the API
      # stays consistent for things like Deadline that can become
      # empty.
      $change->[0] = '' if !defined $change->[0];
      $change->[1] = '' if !defined $change->[1];
      $hash{changes}->{$api_field} = {
        removed => $self->type('string', $change->[0]),
        added   => $self->type('string', $change->[1])
      };
    }

    push(@result, \%hash);
  }

  return {bugs => \@result};
}

sub create {
  my ($self, $params) = @_;
  my $dbh = Bugzilla->dbh;

  # BMO: Don't allow updating of bugs if disabled
  if (Bugzilla->params->{disable_bug_updates}) {
    ThrowErrorPage(
      'bug/process/updates-disabled.html.tmpl',
      'Bug updates are currently disabled.'
    );
  }

  Bugzilla->login(LOGIN_REQUIRED);

  # Some fields cannot be sent to Bugzilla::Bug->create
  foreach my $key (qw(login password token)) {
    delete $params->{$key};
  }

  $params = Bugzilla::Bug::map_fields($params);

  # Define the bug file method if missing
  $params->{filed_via} //= 'api';

  my $flags = delete $params->{flags};

  # We start a nested transaction in case flag setting fails
  # we want the bug creation to roll back as well.
  $dbh->bz_start_transaction();

  my $bug = Bugzilla::Bug->create($params);

  # Set bug flags
  if ($flags) {
    my ($flags, $new_flags) = extract_flags($flags, $bug);
    $bug->set_flags($flags, $new_flags);
    $bug->update($bug->creation_ts);
  }

  $dbh->bz_commit_transaction();

  $bug->send_changes();

  return {id => $self->type('int', $bug->bug_id)};
}

sub legal_values {
  my ($self, $params) = @_;

  Bugzilla->switch_to_shadow_db();

  defined $params->{field}
    or ThrowCodeError('param_required', {param => 'field'});

  my $field = Bugzilla::Bug::FIELD_MAP->{$params->{field}} || $params->{field};

  my @global_selects = @{Bugzilla->fields({is_select => 1, is_abnormal => 0})};

  my $values;
  if (grep($_->name eq $field, @global_selects)) {

    # The field is a valid one.
    $values = get_legal_field_values($field);
  }
  elsif (grep($_ eq $field, PRODUCT_SPECIFIC_FIELDS)) {
    my $id = $params->{product_id};
    defined $id
      || ThrowCodeError('param_required',
      {function => 'Bug.legal_values', param => 'product_id'});
    grep($_->id eq $id, @{Bugzilla->user->get_accessible_products})
      || ThrowUserError('product_access_denied', {id => $id});

    my $product = new Bugzilla::Product($id);
    my @objects;
    if ($field eq 'version') {
      @objects = @{$product->versions};
    }
    elsif ($field eq 'target_milestone') {
      @objects = @{$product->milestones};
    }
    elsif ($field eq 'component') {
      @objects = @{$product->components};
    }

    $values = [map { $_->name } @objects];
  }
  else {
    ThrowCodeError('invalid_field_name', {field => $params->{field}});
  }

  my @result;
  foreach my $val (@$values) {
    push(@result, $self->type('string', $val));
  }

  return {values => \@result};
}

sub add_attachment {
  my ($self, $params) = validate(@_, 'ids');
  my $dbh = Bugzilla->dbh;

  # BMO: Don't allow updating of bugs if disabled
  if (Bugzilla->params->{disable_bug_updates}) {
    ThrowErrorPage(
      'bug/process/updates-disabled.html.tmpl',
      'Bug updates are currently disabled.'
    );
  }

  Bugzilla->login(LOGIN_REQUIRED);
  defined $params->{ids}  || ThrowCodeError('param_required', {param => 'ids'});
  defined $params->{data} || ThrowCodeError('param_required', {param => 'data'});

  my @bugs = map { Bugzilla::Bug->check($_) } @{$params->{ids}};
  foreach my $bug (@bugs) {
    Bugzilla->user->can_edit_product($bug->product_id)
      || ThrowUserError("product_edit_denied", {product => $bug->product});
  }

  my @created;
  $dbh->bz_start_transaction();
  my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

  my $flags     = delete $params->{flags};
  my $comment   = delete $params->{comment};
  my $bug_flags = delete $params->{bug_flags};

  $comment = $comment ? trim($comment) : '';

  foreach my $bug (@bugs) {
    my $attachment = Bugzilla::Attachment->create({
      bug         => $bug,
      creation_ts => $timestamp,
      data        => $params->{data},
      description => $params->{summary},
      filename    => $params->{file_name},
      mimetype    => $params->{content_type},
      ispatch     => $params->{is_patch},
      isprivate   => $params->{is_private},
    });

    if ($flags) {
      my ($old_flags, $new_flags) = extract_flags($flags, $bug, $attachment);
      $attachment->set_flags($old_flags, $new_flags);
    }

    $attachment->update($timestamp);

    # The comment has to be added even if it's empty
    $bug->add_comment(
      $comment,
      {
        isprivate  => $attachment->isprivate,
        type       => CMT_ATTACHMENT_CREATED,
        extra_data => $attachment->id
      }
    );

    if ($bug_flags) {
      my ($old_flags, $new_flags) = extract_flags($bug_flags, $bug);
      $bug->set_flags($old_flags, $new_flags);
    }

    push(@created, $attachment);
  }
  $_->bug->update($timestamp) foreach @created;
  $dbh->bz_commit_transaction();

  $_->send_changes() foreach @bugs;

  my %attachments
    = map { $_->id => $self->_attachment_to_hash($_, $params) } @created;

  return {attachments => \%attachments};
}

sub update_attachment {
  my ($self, $params) = validate(@_, 'ids');

  my $user = Bugzilla->login(LOGIN_REQUIRED);
  my $dbh  = Bugzilla->dbh;

  my $ids = delete $params->{ids};
  defined $ids || ThrowCodeError('param_required', {param => 'ids'});

  # Some fields cannot be sent to set_all
  foreach my $key (qw(login password token)) {
    delete $params->{$key};
  }

  $params = translate($params, ATTACHMENT_MAPPED_SETTERS);

  # Get all the attachments, after verifying that they exist and are editable
  my @attachments = ();
  my %bugs        = ();
  foreach my $id (@$ids) {
    my $attachment = Bugzilla::Attachment->new($id)
      || ThrowUserError("invalid_attach_id", {attach_id => $id});
    my $bug = $attachment->bug;
    $attachment->_check_bug;

    push @attachments, $attachment;
    $bugs{$bug->id} = $bug;
  }

  my $flags     = delete $params->{flags};
  my $comment   = delete $params->{comment};
  my $bug_flags = delete $params->{bug_flags};

  $comment = $comment ? trim($comment) : '';

  # Update the values
  foreach my $attachment (@attachments) {
    my ($update_flags, $new_flags)
      = $flags ? extract_flags($flags, $attachment->bug, $attachment) : ([], []);
    if ($attachment->validate_can_edit) {
      $attachment->set_all($params);
      $attachment->set_flags($update_flags, $new_flags) if $flags;
    }
    elsif (scalar @$update_flags && !scalar(@$new_flags) && !scalar keys %$params) {

      # Requestees can set flags targeted to them, even if they cannot
      # edit the attachment. Flag setters can edit their own flags too.
      my %flag_list = map { $_->{id} => $_ } @$update_flags;
      my $flag_objs = Bugzilla::Flag->new_from_list([keys %flag_list]);
      my @editable_flags;
      foreach my $flag_obj (@$flag_objs) {
        if ($flag_obj->setter_id == $user->id
          || ($flag_obj->requestee_id && $flag_obj->requestee_id == $user->id))
        {
          push(@editable_flags, $flag_list{$flag_obj->id});
        }
      }
      if (!scalar @editable_flags) {
        ThrowUserError("illegal_attachment_edit", {attach_id => $attachment->id});
      }
      $attachment->set_flags(\@editable_flags, []);
    }
    else {
      ThrowUserError("illegal_attachment_edit", {attach_id => $attachment->id});
    }
  }

  $dbh->bz_start_transaction();

  # Do the actual update and get information to return to user
  my @result;
  foreach my $attachment (@attachments) {
    my $changes = $attachment->update();
    my $bug     = $attachment->bug;

    if ($comment) {
      $bug->add_comment(
        $comment,
        {
          isprivate  => $attachment->isprivate,
          type       => CMT_ATTACHMENT_UPDATED,
          extra_data => $attachment->id
        }
      );
    }

    if ($bug_flags) {
      my ($old_flags, $new_flags) = extract_flags($bug_flags, $bug);
      $bug->set_flags($old_flags, $new_flags);
    }

    $changes = translate($changes, ATTACHMENT_MAPPED_RETURNS);

    my %hash = (
      id               => $self->type('int',      $attachment->id),
      last_change_time => $self->type('dateTime', $attachment->modification_time),
      changes          => {},
    );

    foreach my $field (keys %$changes) {
      my $change = $changes->{$field};

      # We normalize undef to an empty string, so that the API
      # stays consistent for things like Deadline that can become
      # empty.
      $hash{changes}->{$field} = {
        removed => $self->type('string', $change->[0] // ''),
        added   => $self->type('string', $change->[1] // '')
      };
    }

    push(@result, \%hash);
  }

  $dbh->bz_commit_transaction();

  # Email users about the change
  foreach my $bug (values %bugs) {
    $bug->update();
    $bug->send_changes();
  }

  # Return the information to the user
  return {attachments => \@result};
}

sub add_comment {
  my ($self, $params) = @_;

  # BMO: Don't allow updating of bugs if disabled
  if (Bugzilla->params->{disable_bug_updates}) {
    ThrowErrorPage(
      'bug/process/updates-disabled.html.tmpl',
      'Bug updates are currently disabled.'
    );
  }

  #The user must login in order add a comment
  Bugzilla->login(LOGIN_REQUIRED);

  # Check parameters
  defined $params->{id} || ThrowCodeError('param_required', {param => 'id'});
  my $comment = $params->{comment};
  (defined $comment && trim($comment) ne '')
    || ThrowCodeError('param_required', {param => 'comment'});

  my $bug = Bugzilla::Bug->check($params->{id});

  Bugzilla->user->can_edit_product($bug->product_id)
    || ThrowUserError("product_edit_denied", {product => $bug->product});

  # Backwards-compatibility for versions before 3.6
  if (defined $params->{private}) {
    $params->{is_private} = delete $params->{private};
  }

  # Append comment
  $bug->add_comment(
    $comment,
    {
      isprivate   => $params->{is_private},
      work_time   => $params->{work_time},
      is_markdown => (defined $params->{is_markdown} ? $params->{is_markdown} : 0)
    }
  );

  # Add comment tags
  $bug->set_all({comment_tags => $params->{comment_tags}})
    if defined $params->{comment_tags};

  # Capture the call to bug->update (which creates the new comment) in
  # a transaction so we're sure to get the correct comment_id.

  my $dbh = Bugzilla->dbh;
  $dbh->bz_start_transaction();

  $bug->update();

  my $new_comment_id = $dbh->bz_last_key('longdescs', 'comment_id');

  $dbh->bz_commit_transaction();

  # Send mail.
  Bugzilla::BugMail::Send($bug->bug_id, {changer => Bugzilla->user});

  return {id => $self->type('int', $new_comment_id)};
}

sub update_see_also {
  my ($self, $params) = @_;

  # BMO: Don't allow updating of bugs if disabled
  if (Bugzilla->params->{disable_bug_updates}) {
    ThrowErrorPage(
      'bug/process/updates-disabled.html.tmpl',
      'Bug updates are currently disabled.'
    );
  }

  my $user = Bugzilla->login(LOGIN_REQUIRED);

  # Check parameters
  $params->{ids} || ThrowCodeError('param_required', {param => 'id'});
  my ($add, $remove) = @$params{qw(add remove)};
  ($add || $remove)
    or ThrowCodeError('params_required', {params => ['add', 'remove']});

  my @bugs;
  foreach my $id (@{$params->{ids}}) {
    my $bug = Bugzilla::Bug->check($id);
    $user->can_edit_product($bug->product_id)
      || ThrowUserError("product_edit_denied", {product => $bug->product});
    push(@bugs, $bug);
    if ($remove) {
      $bug->remove_see_also($_) foreach @$remove;
    }
    if ($add) {
      $bug->add_see_also($_) foreach @$add;
    }
  }

  my %changes;
  foreach my $bug (@bugs) {
    my $change = $bug->update();
    if (my $see_also = $change->{see_also}) {
      $changes{$bug->id}->{see_also} = {
        removed => [split(', ', $see_also->[0])],
        added   => [split(', ', $see_also->[1])],
      };
    }
    else {
      # We still want a changes entry, for API consistency.
      $changes{$bug->id}->{see_also} = {added => [], removed => []};
    }

    Bugzilla::BugMail::Send($bug->id, {changer => $user});
  }

  return {changes => \%changes};
}

sub attachments {
  my ($self, $params) = validate(@_, 'ids', 'attachment_ids');

  Bugzilla->switch_to_shadow_db() unless Bugzilla->user->id;

  if (!(defined $params->{ids} or defined $params->{attachment_ids})) {
    ThrowCodeError('param_required',
      {function => 'Bug.attachments', params => ['ids', 'attachment_ids']});
  }

  my $ids        = $params->{ids}            || [];
  my $attach_ids = $params->{attachment_ids} || [];

  unless (Bugzilla->user->id) {
    Bugzilla->check_rate_limit("get_attachments", remote_ip());
  }

  my %bugs;
  foreach my $bug_id (@$ids) {
    my $bug = Bugzilla::Bug->check($bug_id);
    $bugs{$bug->id} = [];
    foreach my $attach (@{$bug->attachments}) {
      push @{$bugs{$bug->id}}, $self->_attachment_to_hash($attach, $params);
    }
  }

  my %attachments;
  my @log_attachments;
  foreach my $attach (@{Bugzilla::Attachment->new_from_list($attach_ids)}) {
    Bugzilla::Bug->check($attach->bug_id);
    if ($attach->isprivate && !Bugzilla->user->is_insider) {
      ThrowUserError('auth_failure',
        {action => 'access', object => 'attachment', attach_id => $attach->id});
    }
    push @log_attachments, $attach;

    $attachments{$attach->id} = $self->_attachment_to_hash($attach, $params);
  }

  if (Bugzilla->user->id) {
    foreach my $attachment (@log_attachments) {
      Bugzilla->log_user_request($attachment->bug_id, $attachment->id,
        "attachment-get");
    }
  }

  return {bugs => \%bugs, attachments => \%attachments};
}

sub flag_types {
  my ($self, $params) = @_;
  my $dbh  = Bugzilla->switch_to_shadow_db();
  my $user = Bugzilla->user;

  defined $params->{product}
    || ThrowCodeError('param_required',
    {function => 'Bug.flag_types', param => 'product'});

  my $product   = delete $params->{product};
  my $component = delete $params->{component};

  $product = Bugzilla::Product->check({name => $product, cache => 1});
  $component
    = Bugzilla::Component->check(
    {name => $component, product => $product, cache => 1})
    if $component;

  my $flag_params = {product_id => $product->id};
  $flag_params->{component_id} = $component->id if $component;
  my $matched_flag_types = Bugzilla::FlagType::match($flag_params);

  my $flag_types = {bug => [], attachment => []};
  foreach my $flag_type (@$matched_flag_types) {
    push(@{$flag_types->{bug}}, $self->_flagtype_to_hash($flag_type, $product))
      if $flag_type->target_type eq 'bug';
    push(
      @{$flag_types->{attachment}},
      $self->_flagtype_to_hash($flag_type, $product)
    ) if $flag_type->target_type eq 'attachment';
  }

  return $flag_types;
}

sub update_comment_tags {
  my ($self, $params) = @_;

  my $user = Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->params->{'comment_taggers_group'}
    || ThrowUserError("comment_tag_disabled");
  $user->can_tag_comments || ThrowUserError(
    "auth_failure",
    {
      group  => Bugzilla->params->{'comment_taggers_group'},
      action => "update",
      object => "comment_tags"
    }
  );

  my $comment_id = $params->{comment_id} // ThrowCodeError('param_required',
    {function => 'Bug.update_comment_tags', param => 'comment_id'});

  my $comment = Bugzilla::Comment->new($comment_id) || return [];
  $comment->bug->check_is_visible();
  if ($comment->is_private && !$user->is_insider) {
    ThrowUserError('comment_is_private', {id => $comment_id});
  }

  my $dbh = Bugzilla->dbh;
  $dbh->bz_start_transaction();
  foreach my $tag (@{$params->{add} || []}) {
    $comment->add_tag($tag) if defined $tag;
  }
  foreach my $tag (@{$params->{remove} || []}) {
    $comment->remove_tag($tag) if defined $tag;
  }
  $comment->update();
  $dbh->bz_commit_transaction();

  return $comment->tags;
}

sub search_comment_tags {
  my ($self, $params) = @_;

  Bugzilla->login(LOGIN_REQUIRED);
  Bugzilla->params->{'comment_taggers_group'}
    || ThrowUserError("comment_tag_disabled");
  Bugzilla->user->can_tag_comments || ThrowUserError(
    "auth_failure",
    {
      group  => Bugzilla->params->{'comment_taggers_group'},
      action => "search",
      object => "comment_tags"
    }
  );

  my $query = $params->{query};
  $query // ThrowCodeError('param_required', {param => 'query'});
  my $limit = $params->{limit} || 7;
  detaint_natural($limit)
    || ThrowCodeError('param_must_be_numeric',
    {param => 'limit', function => 'Bug.search_comment_tags'});


  my $tags
    = Bugzilla::Comment::TagWeights->match({
    WHERE => {'tag LIKE ?' => "\%$query\%",}, LIMIT => $limit,
    });
  return [map { $_->tag } @$tags];
}

##############################
# Private Helper Subroutines #
##############################

# A helper for get() and search(). This is done in this fashion in order
# to produce a stable API and to explicitly type return values.
# The internals of Bugzilla::Bug are not stable enough to just
# return them directly.

sub _bug_to_hash {
  my ($self, $bug, $params) = @_;
  my $user = Bugzilla->user;

  # All the basic bug attributes are here, in alphabetical order.
  # A bug attribute is "basic" if it doesn't require an additional
  # database call to get the info.
  my %item = %{filter $params,
    {
      alias            => $self->type('string',  $bug->alias),
      id               => $self->type('int',     $bug->bug_id),
      is_confirmed     => $self->type('boolean', $bug->everconfirmed),
      op_sys           => $self->type('string',  $bug->op_sys),
      platform         => $self->type('string',  $bug->rep_platform),
      priority         => $self->type('string',  $bug->priority),
      resolution       => $self->type('string',  $bug->resolution),
      severity         => $self->type('string',  $bug->bug_severity),
      status           => $self->type('string',  $bug->bug_status),
      summary          => $self->type('string',  $bug->short_desc),
      target_milestone => $self->type('string',  $bug->target_milestone),
      type             => $self->type('string',  $bug->bug_type),
      url              => $self->type('string',  $bug->bug_file_loc),
      version          => $self->type('string',  $bug->version),
      whiteboard       => $self->type('string',  $bug->status_whiteboard),
    }
  };

  state $voting_enabled //= $bug->can('votes') ? 1 : 0;
  if ($voting_enabled && filter_wants $params, 'votes') {
    $item{votes} = $self->type('int', $bug->votes);
  }

  # First we handle any fields that require extra work (such as date parsing
  # or SQL calls).
  if (filter_wants $params, 'assigned_to') {
    $item{'assigned_to'} = $self->type('email', $bug->assigned_to->login);
    $item{'assigned_to_detail'}
      = $self->_user_to_hash($bug->assigned_to, $params, undef, 'assigned_to');
  }
  if (filter_wants $params, 'attachments', ['extra']) {
    my @result;
    foreach my $attachment (@{$bug->attachments}) {
      next if $attachment->isprivate && !$user->is_insider;
      push(@result,
        $self->_attachment_to_hash($attachment, $params, ['extra'], 'attachments'));
    }
    $item{'attachments'} = \@result;
  }
  if (filter_wants $params, 'blocks') {
    my @blocks = map { $self->type('int', $_) } @{$bug->blocked};
    $item{'blocks'} = \@blocks;
  }
  if (filter_wants $params, 'classification') {
    $item{classification} = $self->type('string', $bug->classification);
  }
  if (filter_wants $params, 'comments', ['extra']) {
    my @result;
    my $comments = $bug->comments(
      {order => 'oldest_to_newest', after => $params->{new_since}});
    foreach my $comment (@$comments) {
      next if $comment->is_private && !$user->is_insider;
      push(@result,
        $self->_translate_comment($comment, $params, ['extra'], 'comments'));
    }
    $item{'comments'} = \@result;
  }
  if (filter_wants $params, 'component') {
    $item{component} = $self->type('string', $bug->component);
  }
  if (filter_wants $params, 'cc') {
    my @cc = map { $self->type('email', $_) } @{$bug->cc || []};
    $item{'cc'} = \@cc;
    $item{'cc_detail'}
      = [map { $self->_user_to_hash($_, $params, undef, 'cc') } @{$bug->cc_users}];
  }
  if (filter_wants $params, 'creation_time') {
    $item{'creation_time'} = $self->type('dateTime', $bug->creation_ts);
  }
  if (filter_wants $params, 'creator') {
    $item{'creator'} = $self->type('email', $bug->reporter->login);
    $item{'creator_detail'}
      = $self->_user_to_hash($bug->reporter, $params, undef, 'creator');
  }
  if (filter_wants $params, 'depends_on') {
    my @depends_on = map { $self->type('int', $_) } @{$bug->dependson};
    $item{'depends_on'} = \@depends_on;
  }
  if (filter_wants $params, 'description', ['extra']) {
    my $comment = Bugzilla::Comment->match({bug_id => $bug->id, LIMIT => 1})->[0];
    $item{'description'}
      = ($comment && (!$comment->is_private || Bugzilla->user->is_insider))
      ? $comment->body
      : '';
  }
  if (filter_wants $params, 'dupe_of') {
    $item{'dupe_of'} = $self->type('int', $bug->dup_id);
  }
  if (filter_wants $params, 'duplicates') {
    $item{'duplicates'} = [map { $self->type('int', $_->id) } @{$bug->duplicates}];
  }
  if (filter_wants $params, 'filed_via', ['extra']) {
    $item{'filed_via'} = $self->type('string', $bug->filed_via);
  }
  if (filter_wants $params, 'groups') {
    my @groups = map { $self->type('string', $_->name) } @{$bug->groups_in};
    $item{'groups'} = \@groups;
  }
  if (filter_wants $params, 'history', ['extra']) {
    my @result;
    my ($activity)
      = Bugzilla::Bug::GetBugActivity($bug->id, undef, $params->{new_since}, 1);
    foreach my $changeset (@$activity) {
      push(@result,
        $self->_changeset_to_hash($changeset, $params, ['extra'], 'history'));
    }
    $item{'history'} = \@result;
  }
  if (filter_wants $params, 'is_open') {
    $item{'is_open'} = $self->type('boolean', $bug->status->is_open);
  }
  if (filter_wants $params, 'keywords') {
    my @keywords = map { $self->type('string', $_->name) } @{$bug->keyword_objects};
    $item{'keywords'} = \@keywords;
  }
  if (filter_wants $params, 'last_change_time') {
    $item{'last_change_time'} = $self->type('dateTime', $bug->delta_ts);
  }
  if (filter_wants $params, 'product') {
    $item{product} = $self->type('string', $bug->product);
  }
  if (filter_wants $params, 'qa_contact') {
    my $qa_login = $bug->qa_contact ? $bug->qa_contact->login : '';
    $item{'qa_contact'} = $self->type('email', $qa_login);
    if ($bug->qa_contact) {
      $item{'qa_contact_detail'}
        = $self->_user_to_hash($bug->qa_contact, $params, undef, 'qa_contact');
    }
  }
  if (filter_wants $params, 'triage_owner', ['extra']) {
    my $triage_owner = $bug->component_obj->triage_owner;
    $item{'triage_owner'} = $self->type('email', $triage_owner->login);
    if ($triage_owner->login) {
      $item{'triage_owner_detail'}
        = $self->_user_to_hash($triage_owner, $params, ['extra'], 'triage_owner');
    }
  }
  if (filter_wants $params, 'see_also') {
    my @see_also = map { $self->type('string', $_->name) } @{$bug->see_also};
    $item{'see_also'} = \@see_also;
  }
  if (filter_wants $params, 'flags') {
    $item{'flags'} = [map { $self->_flag_to_hash($_) } @{$bug->flags}];
  }

  # Regressions
  if (Bugzilla->params->{use_regression_fields}) {
    if (filter_wants $params, 'regressed_by') {
      my @regressed_by = map { $self->type('int', $_) } @{$bug->regressed_by};
      $item{'regressed_by'} = \@regressed_by;
    }
    if (filter_wants $params, 'regressions') {
      my @regressions = map { $self->type('int', $_) } @{$bug->regresses};
      $item{'regressions'} = \@regressions;
    }
  }

  # And now custom fields
  my @custom_fields = Bugzilla->active_custom_fields(
    {
      product   => $bug->product_obj,
      component => $bug->component_obj,
      bug_id    => $bug->id
    },
    $self->wants_object,
  );
  foreach my $field (@custom_fields) {
    my $name = $field->name;
    next if !filter_wants($params, $name, ['default', 'custom']);
    if ($field->type == FIELD_TYPE_BUG_ID) {
      $item{$name} = $self->type('int', $bug->$name);
    }
    elsif ($field->type == FIELD_TYPE_DATETIME || $field->type == FIELD_TYPE_DATE) {
      my $value = $bug->$name;
      $item{$name} = defined($value) ? $self->type('dateTime', $value) : undef;
    }
    elsif ($field->type == FIELD_TYPE_MULTI_SELECT) {
      my @values = map { $self->type('string', $_) } @{$bug->$name};
      $item{$name} = \@values;
    }
    else {
      $item{$name} = $self->type('string', $bug->$name);
    }
  }

  # Timetracking fields are only sent if the user can see them.
  if ($user->is_timetracker) {
    if (filter_wants $params, 'estimated_time') {
      $item{'estimated_time'} = $self->type('double', $bug->estimated_time);
    }
    if (filter_wants $params, 'remaining_time') {
      $item{'remaining_time'} = $self->type('double', $bug->remaining_time);
    }
    if (filter_wants $params, 'deadline') {

      # No need to format $bug->deadline specially, because Bugzilla::Bug
      # already does it for us.
      $item{'deadline'} = $self->type('string', $bug->deadline);
    }
    if (filter_wants $params, 'actual_time') {
      $item{'actual_time'} = $self->type('double', $bug->actual_time);
    }
  }

  # The "accessible" bits go here because they have long names and it
  # makes the code look nicer to separate them out.
  if (filter_wants $params, 'is_cc_accessible') {
    $item{'is_cc_accessible'} = $self->type('boolean', $bug->cclist_accessible);
  }
  if (filter_wants $params, 'is_creator_accessible') {
    $item{'is_creator_accessible'}
      = $self->type('boolean', $bug->reporter_accessible);
  }

  # BMO - support for special mentors field
  if (filter_wants $params, 'mentors') {
    $item{'mentors'}
      = [map { $self->type('email', $_->login) } @{$bug->mentors || []}];
    $item{'mentors_detail'}
      = [map { $self->_user_to_hash($_, $params, undef, 'mentors') }
        @{$bug->mentors}];
  }

  if (filter_wants $params, 'comment_count') {
    $item{'comment_count'} = $self->type('int', $bug->comment_count);
  }

  if (filter_wants $params, 'counts', ['extra']) {
    $item{'counts'} = {};

    while (my ($key, $value) = each %{$bug->counts}) {
      $item{'counts'}->{$key} = $self->type('int', $value);
    }
  }

  return \%item;
}

sub _user_to_hash {
  my ($self, $user, $filters, $types, $prefix) = @_;
  my $item = filter $filters,
    {
    id        => $self->type('int',    $user->id),
    real_name => $self->type('string', $user->name),
    nick      => $self->type('string', $user->nick),
    name      => $self->type('email',  $user->login),
    email     => $self->type('email',  $user->email),
    },
    $types, $prefix;
  return $item;
}

sub _attachment_to_hash {
  my ($self, $attach, $filters, $types, $prefix) = @_;

  my $item = filter $filters,
    {
    creation_time    => $self->type('dateTime', $attach->attached),
    last_change_time => $self->type('dateTime', $attach->modification_time),
    id               => $self->type('int',      $attach->id),
    bug_id           => $self->type('int',      $attach->bug_id),
    file_name        => $self->type('string',   $attach->filename),
    summary          => $self->type('string',   $attach->description),
    description      => $self->type('string',   $attach->description),
    content_type     => $self->type('string',   $attach->contenttype),
    is_private       => $self->type('int',      $attach->isprivate),
    is_obsolete      => $self->type('int',      $attach->isobsolete),
    is_patch         => $self->type('int',      $attach->ispatch),
    },
    $types, $prefix;

  # creator/attacher require an extra lookup, so we only send them if
  # the filter wants them.
  foreach my $field (qw(creator attacher)) {
    if (filter_wants $filters, $field, $types, $prefix) {
      $item->{$field} = $self->type('email', $attach->attacher->login);
    }
  }

  if (filter_wants $filters, 'creator', $types, $prefix) {
    $item->{'creator_detail'}
      = $self->_user_to_hash($attach->attacher, $filters, undef, 'creator');
  }

  if (filter_wants $filters, 'data', $types, $prefix) {
    $item->{'data'} = $self->type('base64', $attach->data);
  }

  if (filter_wants $filters, 'size', $types, $prefix) {
    $item->{'size'} = $self->type('int', $attach->datasize);
  }

  if (filter_wants $filters, 'flags', $types, $prefix) {
    $item->{'flags'} = [map { $self->_flag_to_hash($_) } @{$attach->flags}];
  }

  return $item;
}

sub _changeset_to_hash {
  my ($self, $changeset, $filters, $types, $prefix) = @_;

  my $item = {
    when    => $self->type('dateTime', $changeset->{when}),
    who     => $self->type('email',    $changeset->{who}),
    changes => []
  };

  foreach my $change (@{$changeset->{changes}}) {
    my $field_name     = delete $change->{fieldname};
    my $api_field_type = $api_field_types{$field_name} || 'string';
    my $api_field_name = $api_field_names{$field_name} || $field_name;
    my $attach_id      = delete $change->{attachid};
    my $comment        = delete $change->{comment};

    $change->{field_name}    = $self->type('string',        $api_field_name);
    $change->{removed}       = $self->type($api_field_type, $change->{removed});
    $change->{added}         = $self->type($api_field_type, $change->{added});
    $change->{attachment_id} = $self->type('int', $attach_id)      if $attach_id;
    $change->{comment_id}    = $self->type('int', $comment->id)    if $comment;
    $change->{comment_count} = $self->type('int', $comment->count) if $comment;

    push(@{$item->{changes}}, $change);
  }

  return filter($filters, $item, $types, $prefix);
}

sub _flag_to_hash {
  my ($self, $flag) = @_;

  my $item = {
    id                => $self->type('int',      $flag->id),
    name              => $self->type('string',   $flag->name),
    type_id           => $self->type('int',      $flag->type_id),
    creation_date     => $self->type('dateTime', $flag->creation_date),
    modification_date => $self->type('dateTime', $flag->modification_date),
    status            => $self->type('string',   $flag->status)
  };

  foreach my $field (qw(setter requestee)) {
    my $field_id = $field . "_id";
    $item->{$field} = $self->type('email', $flag->$field->login)
      if $flag->$field_id;
  }

  return $item;
}

sub _flagtype_to_hash {
  my ($self, $flagtype, $product) = @_;
  my $user = Bugzilla->user;

  my @values = ('X');
  push(@values, '?')
    if ($flagtype->is_requestable && $user->can_request_flag($flagtype));
  push(@values, '+', '-') if $user->can_set_flag($flagtype);

  my $item = {
    id               => $self->type('int',    $flagtype->id),
    name             => $self->type('string', $flagtype->name),
    description      => $self->type('string', $flagtype->description),
    type             => $self->type('string', $flagtype->target_type),
    values           => \@values,
    is_active        => $self->type('boolean', $flagtype->is_active),
    is_requesteeble  => $self->type('boolean', $flagtype->is_requesteeble),
    is_multiplicable => $self->type('boolean', $flagtype->is_multiplicable)
  };

  if ($product) {
    my $inclusions
      = $self->_flagtype_clusions_to_hash($flagtype->inclusions, $product->id);
    my $exclusions
      = $self->_flagtype_clusions_to_hash($flagtype->exclusions, $product->id);

    # if we have both inclusions and exclusions, the exclusions are redundant
    $exclusions = [] if @$inclusions && @$exclusions;

    # no need to return anything if there's just "any component"
    $item->{inclusions} = $inclusions if @$inclusions && $inclusions->[0] ne '';
    $item->{exclusions} = $exclusions if @$exclusions && $exclusions->[0] ne '';
  }

  return $item;
}

sub _flagtype_clusions_to_hash {
  my ($self, $clusions, $product_id) = @_;
  my $result = [];
  foreach my $key (keys %$clusions) {
    my ($prod_id, $comp_id) = split(/:/, $clusions->{$key}, 2);
    if ($prod_id == 0 || $prod_id == $product_id) {
      if ($comp_id) {
        my $component = Bugzilla::Component->new({id => $comp_id, cache => 1});
        push @$result, $component->name;
      }
      else {
        return [''];
      }
    }
  }
  return $result;
}

sub _add_update_tokens {
  my ($self, $params, $bugs, $hashes) = @_;

  return if !Bugzilla->user->id;
  return if !filter_wants($params, 'update_token');

  for (my $i = 0; $i < @$bugs; $i++) {
    my $token = issue_hash_token([$bugs->[$i]->id, $bugs->[$i]->delta_ts]);
    $hashes->[$i]->{'update_token'} = $self->type('string', $token);
  }
}

1;
