# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Markdown;
use 5.10.1;
use Moo;

use Encode;
use Mojo::DOM;
use HTML::Escape qw(escape_html);

has 'markdown_parser' => (is => 'lazy');
has 'bugzilla_shorthand' => (
  is      => 'ro',
  default => sub {
    require Bugzilla::Template;
    \&Bugzilla::Template::quoteUrls;
  }
);

sub _build_markdown_parser {
  if (Bugzilla->has_feature('alien_cmark')) {
    require Bugzilla::Markdown::GFM;
    require Bugzilla::Markdown::GFM::Parser;
    return Bugzilla::Markdown::GFM::Parser->new(
      {
        safe => 1,
        hardbreaks =>,
        validate_utf8 => 1,
        strikethrough_double_tilde => 1,
        extensions => [qw( autolink tagfilter table strikethrough)],
      }
    );
  }
  else {
    return undef;
  }
}

sub render_html {
  my ($self, $markdown, $bug, $comment, $user) = @_;
  my $parser             = $self->markdown_parser;
  my $bugzilla_shorthand = $self->bugzilla_shorthand;

  if ($parser) {
    my $html = decode('UTF-8', $parser->render_html($markdown));
    my $dom  = Mojo::DOM->new($html);
    $dom->find('p, li')->map(sub {
      my $node = shift;
      if ($node->type eq 'text') {
        my $text = $node->text;
        $node->content($bugzilla_shorthand->($text));
      }
      return $node;
    });
    return $dom->to_string;
  }
  else {
    return escape_html($markdown);
  }
}

1;
