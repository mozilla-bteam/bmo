# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Classification;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Field;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Product;

use base qw(Bugzilla::Field::ChoiceInterface Bugzilla::Object);

###############################
####    Initialization     ####
###############################

use constant IS_CONFIG => 1;

use constant DB_TABLE   => 'classifications';
use constant LIST_ORDER => 'sortkey, name';

use constant DB_COLUMNS => qw(
  id
  name
  description
  sortkey
);

use constant UPDATE_COLUMNS => qw(
  name
  description
  sortkey
);

use constant VALIDATORS => {
  name        => \&_check_name,
  description => \&_check_description,
  sortkey     => \&_check_sortkey,
};

###############################
####     Constructors     #####
###############################

sub remove_from_db {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  ThrowUserError("classification_not_deletable") if ($self->id == 1);

  $dbh->bz_start_transaction();

  # Reclassify products to the default classification, if needed.
  my $product_ids
    = $dbh->selectcol_arrayref(
    'SELECT id FROM products WHERE classification_id = ?',
    undef, $self->id);

  if (@$product_ids) {
    $dbh->do('UPDATE products SET classification_id = 1 WHERE '
        . $dbh->sql_in('id', $product_ids));
    foreach my $id (@$product_ids) {
      Bugzilla->memcached->clear({table => 'products', id => $id});
    }
    Bugzilla->memcached->clear_config();
  }

  $self->SUPER::remove_from_db();

  $dbh->bz_commit_transaction();

}

###############################
####      Validators       ####
###############################

sub _check_name {
  my ($invocant, $name) = @_;

  $name = trim($name);
  $name || ThrowUserError('classification_not_specified');

  if (length($name) > MAX_CLASSIFICATION_SIZE) {
    ThrowUserError('classification_name_too_long', {'name' => $name});
  }

  my $classification = new Bugzilla::Classification({name => $name});
  if ($classification && (!ref $invocant || $classification->id != $invocant->id))
  {
    ThrowUserError("classification_already_exists",
      {name => $classification->name});
  }
  return $name;
}

sub _check_description {
  my ($invocant, $description) = @_;

  $description = trim($description || '');
  return $description;
}

sub _check_sortkey {
  my ($invocant, $sortkey) = @_;

  $sortkey ||= 0;
  my $stored_sortkey = $sortkey;
  if (!detaint_natural($sortkey) || $sortkey > MAX_SMALLINT) {
    ThrowUserError('classification_invalid_sortkey',
      {'sortkey' => $stored_sortkey});
  }
  return $sortkey;
}

#####################################
# Implement Bugzilla::Field::Choice #
#####################################

use constant FIELD_NAME => 'classification';
use constant is_default => 0;
use constant is_active  => 1;

###############################
####       Methods         ####
###############################

sub set_name        { $_[0]->set('name',        $_[1]); }
sub set_description { $_[0]->set('description', $_[1]); }
sub set_sortkey     { $_[0]->set('sortkey',     $_[1]); }

sub product_count {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  if (!defined $self->{'product_count'}) {
    $self->{'product_count'} = $dbh->selectrow_array(
      q{
            SELECT COUNT(*) FROM products
            WHERE classification_id = ?}, undef, $self->id
    ) || 0;
  }
  return $self->{'product_count'};
}

sub products {
  my $self = shift;
  my $dbh  = Bugzilla->dbh;

  if (!$self->{'products'}) {
    my $product_ids = $dbh->selectcol_arrayref(
      q{
            SELECT id FROM products
            WHERE classification_id = ?
            ORDER BY name}, undef, $self->id
    );

    $self->{'products'} = Bugzilla::Product->new_from_list($product_ids);
  }
  return $self->{'products'};
}

###############################
####      Accessors        ####
###############################

sub description { return $_[0]->{'description'}; }
sub sortkey     { return $_[0]->{'sortkey'}; }

1;

__END__

=head1 NAME

Bugzilla::Classification - Bugzilla classification class.

=head1 SYNOPSIS

    use Bugzilla::Classification;

    my $classification = new Bugzilla::Classification(1);
    my $classification = new Bugzilla::Classification({name => 'Acme'});

    my $id = $classification->id;
    my $name = $classification->name;
    my $description = $classification->description;
    my $sortkey = $classification->sortkey;
    my $product_count = $classification->product_count;
    my $products = $classification->products;

=head1 DESCRIPTION

Classification.pm represents a classification object. It is an
implementation of L<Bugzilla::Object>, and thus provides all methods
that L<Bugzilla::Object> provides.

The methods that are specific to C<Bugzilla::Classification> are listed
below.

A Classification is a higher-level grouping of Products.

=head1 METHODS

=over

=item C<product_count()>

 Description: Returns the total number of products that belong to
              the classification.

 Params:      none.

 Returns:     Integer - The total of products inside the classification.

=item C<products>

 Description: Returns all products of the classification.

 Params:      none.

 Returns:     A reference to an array of Bugzilla::Product objects.

=back

=cut
