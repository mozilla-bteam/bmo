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
use Bugzilla::Bug;
use Bugzilla::ChangeSet;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Search;
use List::MoreUtils qw(all);
use Getopt::Long;

my ($product_name, $version, $milestone, $save_to);
$save_to = 'rewrite_milestones_and_versions.json';

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
Bugzilla->error_mode(ERROR_MODE_DIE);

GetOptions(
    'product|p=s' => \$product_name,
    'version|V=s' => \$version,
    'milestone|M=s' => \$milestone,
    'save-to=s'     => \$save_to,
);

die "--product (-p) is required!\n" unless $product_name;

my $product = Bugzilla::Product->check({name => $product_name});

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$auto_user->{groups} = [ Bugzilla::Group->get_all ];
$auto_user->{bless_groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($auto_user);

my $change_set = Bugzilla::ChangeSet->new(
    user => { name => $auto_user->login },
    # This is a string, as that makes it easier to serialize.
    before_run => q{
        no warnings 'redefine';
        *Bugzilla::Milestone::is_active = sub { 1 };
        *Bugzilla::Version::is_active = sub { 1 };
    },
    after_update => {
        'Bugzilla::Bug' => q{
            my ($bug, $ts) = @_;
            Bugzilla->dbh->do("UPDATE bugs SET lastdiffed = ? WHERE bug_id = ?",
                    undef, $ts, $bug->id);
        },
    },
);

my ( $version_like, $translate_version )
    = make_translator( $dbh, 'version', 'versions', $product, $version, $change_set );

my ( $milestone_like, $translate_milestone )
    = make_translator( $dbh, 'target_milestone', 'milestones', $product, $milestone, $change_set );

my $bug_ids = $dbh->selectcol_arrayref(
    q{
        SELECT bug_id
          FROM bugs
        WHERE product_id = ?
          AND ( version LIKE ? OR target_milestone LIKE ? )
    },
    undef,
    $product->id,
    $version_like,
    $milestone_like,
);

my $bug_count = @$bug_ids;
if ($bug_count == 0) {
    warn "There are no bugs to translate.\n";
    exit 1;
}


foreach my $bug_id (@$bug_ids) {
    my $bug_update = $change_set->new_update(
        class        => 'Bugzilla::Bug',
        id           => $bug_id,
    );

    my $changes = 0;
    $changes += $translate_version->($bug_update);
    $changes += $translate_milestone->($bug_update);
    next unless $changes;

    # make sure memory is cleaned up.
    Bugzilla::Hook::process('request_cleanup');
    Bugzilla::Bug->CLEANUP;
    Bugzilla->clear_request_cache(except => [qw(user dbh dbh_main dbh_shadow memcached)]);
}

Bugzilla->memcached->clear_all();

$change_set->save("rewrite-milestones-and-versions.json");


sub make_translator {
    my ($dbh, $field, $table, $product, $spec, $change_set) = @_;
    my ($from, $to, $force);
    if ($spec =~ /^\s*(.+?)\s*->\s*(.+?)\s*(!)?$/) {
        ($from, $to, $force) = ($1, $2, !!$3);
    }

    my $from_like = do { my $f = $from; $f =~ s/\*/%/g; $f };
    my $from_re   = do { my $f = quotemeta $from; $f =~ s/\\\*/(.+)/g; qr/^$f$/ };
    my $to_sub    = sub { my $t = $to; $t =~ s/\*/shift @_/ge; $t; };
    my $translate = sub { my ($s) = @_; $to_sub->($s =~ $from_re); };

    my $values = $dbh->selectcol_arrayref(
        qq{
            SELECT value
            FROM $table
            WHERE value LIKE ?
            AND product_id = ?
        },
        undef,
        $from_like,
        $product->id,
    );

    die "Did not find any values matching $from\n" unless @$values;

    my %value_map = ( map { $_ => $translate->($_) } @$values );
    unless (all { defined } values %value_map) {
        my $untranslated = join("\n * ", grep { not defined $value_map{$_} } keys %value_map );
        die "Unable to map all values:\n * $untranslated\n";
    }

    my @new_values = sort values %value_map;
    my $qmarks = join(", ", ('?') x @new_values);
    my $found_values = $dbh->selectcol_arrayref(
        qq{
            SELECT value
            FROM $table
            WHERE product_id = ?
            AND value IN ($qmarks)
        },
        undef,
        $product->id,
        @new_values,
    );

    if (@$found_values != @new_values) {
        my %found = map { $_ => 1 } @$found_values;
        my @missing = grep { not $found{$_} } @new_values;
        die "No missing values" unless @missing;

        if ($force) {
            my $class = $field eq 'version' ? 'Bugzilla::Version' : 'Bugzilla::Milestone';
            warn "Creating $field values\n * ", join("\n * ", @missing), "\n";
            foreach my $value (@missing) {
                $change_set->new_create(
                    class => $class,
                    args => {
                        value    => $value,
                        isactive => 1,
                        product  => $change_set->new_reference($product),
                    },
                );
            }
        }
        else {
            my $missing = join("\n * ", @missing);
            die "Missing $field values\n * $missing\n";
        }
    }

    my $func = sub {
        my ($bug_update) = @_;
        my $old = $bug_update->get($field);
        my $new = $value_map{$old};
        if ($new && $old ne $new) {
            $bug_update->set($field, $new);
            return 1;
        }
        else {
            return 0;
        }
    };
    return ($from_like, $func);
}

