# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Version;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object Exporter);

@Bugzilla::Version::EXPORT = qw(vers_cmp);

use Bugzilla::Util;
use Bugzilla::Error;

use Scalar::Util qw(blessed);

################################
#####   Initialization     #####
################################

use constant DEFAULT_VERSION => 'unspecified';

use constant DB_TABLE   => 'versions';
use constant NAME_FIELD => 'value';

# This is "id" because it has to be filled in and id is probably the fastest.
# We do a custom sort in new_from_list below.
use constant LIST_ORDER => 'id';

use constant DB_COLUMNS => qw(
  id
  value
  product_id
  isactive
);

use constant REQUIRED_FIELD_MAP => {product_id => 'product',};

use constant UPDATE_COLUMNS => qw(
  value
  isactive
);

use constant VALIDATORS => {
  product  => \&_check_product,
  value    => \&_check_value,
  isactive => \&Bugzilla::Object::check_boolean,
};

use constant VALIDATOR_DEPENDENCIES => {value => ['product'],};

################################
# Methods
################################

sub new {
  my $class = shift;
  my $param = shift;
  my $dbh   = Bugzilla->dbh;

  my $product;
  if (ref $param) {
    $product = $param->{product};
    my $name = $param->{name};
    if (!defined $product) {
      ThrowCodeError('bad_arg', {argument => 'product', function => "${class}::new"});
    }
    if (!defined $name) {
      ThrowCodeError('bad_arg', {argument => 'name', function => "${class}::new"});
    }

    my $condition = 'product_id = ? AND value = ?';
    my @values = ($product->id, $name);
    $param = {condition => $condition, values => \@values};
  }

  unshift @_, $param;
  return $class->SUPER::new(@_);
}

sub new_from_list {
  my $self = shift;
  my $list = $self->SUPER::new_from_list(@_);
  return [sort { vers_cmp(lc($a->name), lc($b->name)) } @$list];
}

sub run_create_validators {
  my $class   = shift;
  my $params  = $class->SUPER::run_create_validators(@_);
  my $product = delete $params->{product};
  $params->{product_id} = $product->id;
  return $params;
}

sub bug_count {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  if (!defined $self->{'bug_count'}) {
    $self->{'bug_count'} = $dbh->selectrow_array(
      qq{
            SELECT COUNT(*) FROM bugs
            WHERE product_id = ? AND version = ?}, undef,
      ($self->product_id, $self->name)
    ) || 0;
  }
  return $self->{'bug_count'};
}

sub update {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  $dbh->bz_start_transaction();
  my ($changes, $old_self) = $self->SUPER::update(@_);

  if (exists $changes->{value}) {

    # The version value is stored in the bugs table instead of its ID.
    $dbh->do(
      'UPDATE bugs SET version = ?
                  WHERE version = ? AND product_id = ?', undef,
      ($self->name, $old_self->name, $self->product_id)
    );

    # The default value also stores the value instead of the ID.
    $dbh->do(
      'UPDATE products SET default_version = ?
                  WHERE id = ? AND default_version = ?', undef,
      ($self->name, $old_self->product_id, $old_self->name)
    );
    Bugzilla->memcached->clear({table => 'products', id => $self->product_id});
  }
  $dbh->bz_commit_transaction();
  Bugzilla->memcached->clear_config();

  return $changes;
}

sub remove_from_db {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  $dbh->bz_start_transaction();

  # The default version cannot be deleted.
  if ($self->name eq $self->product->default_version) {
    ThrowUserError('version_is_default', {version => $self});
  }

  if ($self->bug_count) {

    # We don't want to delete bugs when deleting a version.
    # Bugs concerned are reassigned to the default version.
    my $bug_ids = $dbh->selectcol_arrayref(
      'SELECT bug_id FROM bugs
                                    WHERE product_id = ? AND version = ?',
      undef, ($self->product->id, $self->name)
    );

    my $timestamp = $dbh->selectrow_array('SELECT NOW()');

    $dbh->do(
      'UPDATE bugs SET version = ?, delta_ts = ?
                   WHERE ' . $dbh->sql_in('bug_id', $bug_ids), undef,
      ($self->product->default_version, $timestamp)
    );

    require Bugzilla::Bug;
    import Bugzilla::Bug qw(LogActivityEntry);
    foreach my $bug_id (@$bug_ids) {
      LogActivityEntry($bug_id, 'version', $self->name,
        $self->product->default_version,
        Bugzilla->user->id, $timestamp);
    }
  }
  $self->SUPER::remove_from_db();

  $dbh->bz_commit_transaction();
}

###############################
#####     Accessors        ####
###############################

sub product_id { return $_[0]->{'product_id'}; }
sub is_active  { return $_[0]->{'isactive'}; }

sub product {
  my $self = shift;

  require Bugzilla::Product;
  $self->{'product'}
    ||= Bugzilla::Product->new({id => $self->product_id, cache => 1});
  return $self->{'product'};
}

################################
# Validators
################################

sub set_name      { $_[0]->set('value',    $_[1]); }
sub set_is_active { $_[0]->set('isactive', $_[1]); }

sub _check_value {
  my ($invocant, $name, undef, $params) = @_;
  my $product = blessed($invocant) ? $invocant->product : $params->{product};

  $name = trim($name);
  $name || ThrowUserError('version_blank_name');

  # Remove unprintable characters
  $name = clean_text($name);

  my $version = new Bugzilla::Version({product => $product, name => $name});
  if ($version && (!ref $invocant || $version->id != $invocant->id)) {
    ThrowUserError('version_already_exists',
      {name => $version->name, product => $product->name});
  }
  return $name;
}

sub _check_product {
  my ($invocant, $product) = @_;
  $product
    || ThrowCodeError('param_required',
    {function => "$invocant->create", param => 'product'});
  return Bugzilla->user->check_can_admin_product($product->name);
}

###############################
#####     Functions        ####
###############################

# This is taken straight from Sort::Versions 1.5, which is not included
# with Perl by default.
sub vers_cmp {
  my ($a, $b) = @_;

  # Remove leading zeroes - Bug 344661
  $a =~ s/^0*(\d.+)/$1/;
  $b =~ s/^0*(\d.+)/$1/;

  my @A = ($a =~ /([-.]|\d+|[^-.\d]+)/g);
  my @B = ($b =~ /([-.]|\d+|[^-.\d]+)/g);

  my ($A, $B);
  while (@A and @B) {
    $A = shift @A;
    $B = shift @B;
    if ($A eq '-' and $B eq '-') {
      next;
    }
    elsif ($A eq '-') {
      return -1;
    }
    elsif ($B eq '-') {
      return 1;
    }
    elsif ($A eq '.' and $B eq '.') {
      next;
    }
    elsif ($A eq '.') {
      return -1;
    }
    elsif ($B eq '.') {
      return 1;
    }
    elsif ($A =~ /^\d+$/ and $B =~ /^\d+$/) {
      if ($A =~ /^0/ || $B =~ /^0/) {
        return $A cmp $B if $A cmp $B;
      }
      else {
        return $A <=> $B if $A <=> $B;
      }
    }
    else {
      $A = uc $A;
      $B = uc $B;
      return $A cmp $B if $A cmp $B;
    }
  }
  return @A <=> @B;
}

1;

__END__

=head1 NAME

Bugzilla::Version - Bugzilla product version class.

=head1 SYNOPSIS

    use Bugzilla::Version;

    my $version = new Bugzilla::Version({ name => $name, product => $product });

    my $value = $version->name;
    my $product_id = $version->product_id;
    my $product = $version->product;

    my $version = Bugzilla::Version->create(
        { value => $name, product => $product });

    $version->set_name($new_name);
    $version->update();

    $version->remove_from_db;

=head1 DESCRIPTION

Version.pm represents a Product Version object. It is an implementation
of L<Bugzilla::Object>, and thus provides all methods that
L<Bugzilla::Object> provides.

The methods that are specific to C<Bugzilla::Version> are listed
below.

=head1 METHODS

=over

=item C<bug_count()>

 Description: Returns the total of bugs that belong to the version.

 Params:      none.

 Returns:     Integer with the number of bugs.

=back

=cut
