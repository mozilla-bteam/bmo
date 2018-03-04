#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;

use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs(dirname(__FILE__));
    my $base = File::Spec->catdir($dir, "..");
    lib->import($base, File::Spec->catdir($base, "lib"), File::Spec->catdir($base, qw(local lib perl5)));
    chdir $base;
}

use Bugzilla;
BEGIN { Bugzilla->extensions }

use Bugzilla::DB;
use Bugzilla::Install::DB;
use Bugzilla::Config qw(update_params);

Bugzilla::DB::bz_create_database();

# Clear all keys from Memcached to ensure we see the correct schema.
Bugzilla->memcached->clear_all();

# now get a handle to the database:
my $dbh = Bugzilla->dbh;
# Create the tables, and do any database-specific schema changes.
$dbh->bz_setup_database();
# Populate the tables that hold the values for the <select> fields.
$dbh->bz_populate_enum_tables();

# Using Bugzilla::Field's create() or update() depends on the
# fielddefs table having a modern definition. So, we have to make
# these particular schema changes before we make any other schema changes.
Bugzilla::Install::DB::update_fielddefs_definition();

Bugzilla::Field::populate_field_definitions();

###########################################################################
# Update the tables to the current definition --TABLE--
###########################################################################

Bugzilla::Install::DB::update_table_definitions({});
Bugzilla::Install::init_workflow();
