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

use base qw(Template::Directive);

my $HTML_FILTER = 'Bugzilla::Util::html_quote';
my $URI_FILTER  = 'Template::Filters::url_filter';

our ($PRETTY, $OUTPUT);
*OUTPUT = \$Template::Directive::OUTPUT;
*PRETTY = \$Template::Directive::PRETTY;
*args   = \&Template::Directive::args;

sub filter_ignore {
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
    elsif ($name eq "'uri'") {
        return <<EOF;
# HTML filter
$OUTPUT do {
    my \$output = '';
$block
    $URI_FILTER(\$output);
};
EOF
    }
    elsif ($name eq "'html'") {
        return <<EOF;
# HTML filter
$OUTPUT do {
    my \$output = '';
$block
    $HTML_FILTER(\$output);
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

1;
