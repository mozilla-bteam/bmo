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
use List::MoreUtils qw(any);

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
    return Bugzilla::Markdown::GFM::Parser->new({
      hardbreaks    => 1,
      validate_utf8 => 1,
      safe          => 1,
      extensions    => [qw( autolink tagfilter table strikethrough )],
    });
  }
  else {
    return undef;
  }
}

sub render_html {
  my ($self, $markdown, $bug, $comment, $user) = @_;
  my $parser = $self->markdown_parser;
  return escape_html($markdown) unless $parser;

  no warnings 'utf8'; # this is needed because our perl is so old.
  # This is a bit faster since it doesn't engage the regex engine.
  # Replace < with \x{FDD4}, and remove \x{FDD4}.
  $markdown =~ tr/<\x{FDD4}/\x{FDD4}/d;
  my @valid_text_parent_tags = ('p', 'li', 'td');
  my @bad_tags               = qw( img );
  my $bugzilla_shorthand     = $self->bugzilla_shorthand;
  my $html                   = decode('UTF-8', $parser->render_html($markdown));

  $html =~ s/\x{FDD4}/&lt;/g;
  my $dom = Mojo::DOM->new($html);

  $dom->find(join(', ', @bad_tags))->map('remove');
  $dom->find(join ', ', @valid_text_parent_tags)->map(sub {
    my $node = shift;
    $node->descendant_nodes->map(sub {
      my $child = shift;
      if ( $child->type eq 'text'
        && $child->children->size == 0
        && any { $child->parent->tag eq $_ } @valid_text_parent_tags)
      {
        my $text = $child->content;
        $child->replace(Mojo::DOM->new($bugzilla_shorthand->($text)));
      }
      return $child;
    });
    return $node;
  });
  return $dom->to_string;

}


1;
