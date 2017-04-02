# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This exists to implement the template-before_process hook.
package Bugzilla::Template::Namespace;

use 5.10.1;
use strict;
use warnings;

use base qw(Template::Base);
use List::MoreUtils qw(any);

my @BUGZILLA_HASHES    = qw( request_cache process_cache params localconfig );
my @BUGZILLA_OBJECTS   = qw( cgi user );

use Bugzilla::Template::Directive qw(tt_parse_ident tt_quote tt_dot_op);

# These are also defined in a template, but for BMO we just want to fold them.
my %TERMS = (
    "bug"               => "bug",
    "Bug"               => "Bug",
    "abug"              => "a bug",
    "Abug"              => "A bug",
    "aBug"              => "a Bug",
    "ABug"              => "A Bug",
    "bugs"              => "bugs",
    "Bugs"              => "Bugs",
    "zeroSearchResults" => "Zarro Boogs found",
    "Bugzilla"          => "Bugzilla",
    "BugzillaTitle" => 'Bugzilla@Development',
);

sub ident {
    my ($self, $ident) = @_;
    my ($ns, $ns_args) = tt_parse_ident($ident);

    my $expr;
    if ($ns eq 'terms') {
        my ($key, $key_args) = eval { tt_parse_ident($ident) };
        if ($@) {
            return Bugzilla::Template::Directive->ident([ tt_quote('terms'), 0, @$ident ]);
        }
        die "Unknown terms variable: terms.$key" unless exists $TERMS{$key};
        return tt_quote($TERMS{$key});
    }
    elsif ($ns eq 'Hook') {
        my ($method, $args) = tt_parse_ident($ident);
        die "Bad hook method: $method" unless $method eq 'process';
        $expr = "Bugzilla::Hook::template_process(\$context, $args)";
    }
    elsif ($ns eq 'constants') {
        my ($const, $const_args) = tt_parse_ident($ident);
        die "constants has args!" if $const_args;
        $expr = "Bugzilla::Constants::$const";
        if (my $f = Bugzilla::Constants->can($const)) {
            my $val;
            my $count = ($val) = $f->();
            if ($count > 1) {
                $expr = "[ $expr ]";
            } 
            elsif (ref $val && ref $val eq 'HASH') {
                if (@$ident) {
                    my ($key) = tt_parse_ident($ident);
                    $expr .= "->{$key}";
                }
            }
        }
        # perl will catch invalid constants for us.
    }
    elsif ($ns eq 'Bugzilla') {
        my ($method, $args) = tt_parse_ident($ident);
        if (!Bugzilla->can($method)) {
            die "No such method: Bugzilla->$method";
        }
        $expr = "Bugzilla->$method";

        if ($args) {
            $expr .= "($args)";
        }
        elsif (any { $method eq $_ } @BUGZILLA_HASHES) {
            $expr .= '->{' . $ident->[0] . '}';
            splice @$ident, 0, 2;
        }
        elsif (any { $method eq $_ } @BUGZILLA_OBJECTS) {
            if (@$ident) {
                my ($obj_method, $obj_args) = tt_parse_ident($ident);
                $expr .= "->$obj_method";
                if ($obj_args) {
                    $expr .= "($obj_args)";
                }
            }
        }
    }

    return tt_dot_op($expr, $ident);
}




1;
