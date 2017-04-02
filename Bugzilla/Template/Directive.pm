# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This exists to implement the template-before_process hook.
package Bugzilla::Template::Directive;

use 5.10.1;
use strict;
use warnings;

use base qw(Template::Directive Exporter);

our @EXPORT_OK = qw(tt_parse_ident tt_quote tt_dot_op);

sub use {
    my ( $self, $lnameargs ) = @_;
    my ( $file, $args, $alias ) = @$lnameargs;

    # Both Bugzilla and Hook plugins no longer exist.
    if ($file->[0] eq "'Bugzilla'" ||  $file->[0] eq "'Hook'") {
        return "# IGNORE USE $file->[0]\n";
    }
    else {
        return $self->SUPER::use($lnameargs);
    }
}

sub ident {
    my ($self, $ident) = @_;
    my $name = _dequote($ident->[0]);
    if (defined $name) {
        my $changed = 0;
        if ($name eq 'Param') {
            splice @$ident, 0, 2,
                tt_quote('Bugzilla'), 0, tt_quote('params'), 0, _deref($ident->[1]), 0;
        }
        elsif ($name eq 'display_value') {
            my ($name, $args) = tt_parse_ident($ident);
            my $expr = "Bugzilla::Util::display_value($args)";
            return tt_dot_op($expr, $ident);
        }
    }
    my $result = $self->SUPER::ident($ident);
    return $result;
}

sub filter {
    package Template::Directive;
    our ($PRETTY, $OUTPUT);

    my ($self, $lnameargs, $block) = @_;
    my ($name, $args, $alias) = @$lnameargs;
    $name = shift @$name;
    $args = &args($self, $args);
    $args = $args ? "$args, $alias" : ", undef, $alias"
        if $alias;

    if ($name eq "'none'") {
        return "# NO FILTER\n\n$block";
    }
    elsif ($name eq "'null'") {
        return <<EOF;
# null filter
$OUTPUT do {
    my \$output = '';
$block
    '';
};
EOF
    }
    elsif ($name eq "'html'") {
        return <<EOF;
# HTML filter
$OUTPUT do {
    my \$output = '';
$block
    Bugzilla::Util::html_quote(\$output);
};
EOF
    } else {
        $name .= ", $args" if $args;
        $block = pad($block, 1) if $PRETTY;

        return <<EOF;

# FILTER
$OUTPUT do {
    my \$output = '';
    my \$_tt_filter = \$context->filter($name)
              || \$context->throw(\$context->error);

$block
    
    &\$_tt_filter(\$output);
};
EOF
    }
}

use Carp;
sub tt_parse_ident {
    my ($ident, $debug) = @_;
    if (@$ident) {
        my @save = @$ident;
        my $name = _dequote($ident->[0]);
        my $args   = _deref($ident->[1]);
        if (defined $name) {
            splice @$ident, 0, 2;
            return ($name, $args);
        }
        else {
            confess "expected quoted identifier, got @$ident";
        }
    }
    else {
        die "error";
    }
}

sub tt_quote {
    my ($str) = @_;
    return 'undef' if not defined $str;
    $str =~ s/(['\\])/\\$1/g;
    return qq{'$str'};
}

sub tt_dot_op {
    my ($expr, $ident) = @_;

    my $nelems = @$ident / 2;
    foreach my $e (0..$nelems-1) {
        my $item = $ident->[$e * 2];
        my $args = $ident->[$e * 2 + 1] ? ", $ident->[$e * 2 + 1]" : "";
        $expr = "\$stash->dotop($expr, $item$args)";
    }

    return $expr;
}

sub _dequote {
    my ($str) = @_;
    if ($str =~ /^'(.+)'$/) {
        $str = $1;
        $str =~ s/\\'/'/g;
        return $str;
    }
    return undef;
}

sub _deref {
    my ($str) = @_;
    return undef unless $str;
    if ($str =~ /^\[\s*(.+?)\s*\]$/) {
        return $1;
    }
    return undef;
}

1;
