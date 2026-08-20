#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Bug 2009746 - a whine event subject reaches the Subject: header of the
# generated mail. It used to be interpolated into a block of header text that
# was then parsed by Email::MIME, so control characters in it let the event
# owner inject arbitrary headers.
#
# This exercises the real path: whine/subject.txt.tmpl is rendered, and the
# header set is built by Email::MIME->create exactly as whine.pl does. Both
# defences are covered - the header builder (the control) and clean_text
# (defence in depth).

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);

use Bugzilla::Util qw(clean_text trim);
use Email::MIME;
use Template;
use Test::More;

use constant FROM => 'bugzilla-daemon@example.com';
use constant TO   => 'whine-target@example.com';

# What whine.pl's mail() is expected to produce. Everything other than the four
# headers it asks for is added by Email::MIME->create itself.
use constant EXPECTED_HEADERS => [
  sort qw(From To Subject X-Bugzilla-Type
    Content-Transfer-Encoding Content-Type Date MIME-Version)
];

# Renders whine/subject.txt.tmpl the way whine.pl does. This needs no database
# or Bugzilla object; global/variables.none.tmpl is plain Template Toolkit.
sub render_subject {
  my ($subject) = @_;
  my $tt = Template->new({INCLUDE_PATH => 'template/en/default'})
    or die Template->error;
  my $out = '';
  $tt->process('whine/subject.txt.tmpl', {subject => $subject}, \$out)
    or die $tt->error;
  return trim($out);
}

# Mirrors the header construction in whine.pl's mail(). Returns undef if
# Email::MIME refused the value outright, which a future version is documented
# to start doing instead of replacing the control characters.
sub build_email {
  my ($subject) = @_;
  my $email = eval {
    local $SIG{__WARN__} = sub { };
    Email::MIME->create(
      header_str => [
        From              => FROM,
        To                => TO,
        Subject           => render_subject($subject),
        'X-Bugzilla-Type' => 'whine',
      ],
      parts => [
        Email::MIME->create(
          attributes => {content_type => 'text/plain'},
          body       => 'whine body',
        )
      ],
    );
  };
  return $email;
}

# header_names() de-duplicates, which would hide an injected second To:, so
# look at the raw pairs instead.
sub header_names {
  my ($email) = @_;
  my @pairs = $email->header_pairs;
  my @names;
  while (my ($name) = splice(@pairs, 0, 2)) {
    push @names, $name;
  }
  my @sorted = sort @names;
  return @sorted;
}

sub assert_uninjected {
  my ($subject, $desc) = @_;

  my $email = build_email($subject);
  if (!defined $email) {

    # Email::MIME rejected the value rather than sanitizing it. Still safe.
    pass("$desc: header value rejected outright");
    return;
  }

  is_deeply([header_names($email)], EXPECTED_HEADERS, "$desc: header set intact");
  is($email->header('Bcc'), undef, "$desc: no Bcc header");
  is($email->header('To'),  TO,    "$desc: To header untouched");
  unlike($email->header('Subject'), qr/[\r\n]/, "$desc: Subject has no CR/LF");
  unlike($email->body_str, qr/Injected body/, "$desc: nothing pushed into body");
}

my @injections = (
  ["Nightly bugs\nBcc: attacker\@example.com",   'LF + Bcc'],
  ["Nightly bugs\r\nBcc: attacker\@example.com", 'CRLF + Bcc'],
  ["Nightly bugs\nTo: attacker\@example.com",    'LF + duplicate To'],
  ["Nightly bugs\r\n\r\nInjected body",          'CRLF CRLF body split'],
);

foreach my $case (@injections) {
  my ($raw, $desc) = @$case;

  # The header builder is the control: a hostile subject that never went
  # through clean_text must still not inject.
  assert_uninjected($raw, "$desc: raw subject");

  # clean_text is defence in depth for events stored before editwhines.cgi
  # started rejecting these values.
  assert_uninjected(clean_text($raw), "$desc: sanitized subject");
}

# The template renders a Subject: value and nothing else. If someone
# re-introduces a header line into it, the extra line shows up here and the
# header-set assertions above stop matching EXPECTED_HEADERS.
is(
  render_subject('Nightly bugs'),
  '[Bugzilla] Nightly bugs',
  'template renders the subject as one branded line'
);
is(scalar(grep {/\S/} split(/\n/, render_subject('Nightly bugs'))),
  1, 'template emits no lines beyond the subject');

# whine.pl is a script, not a loadable module, so build_email() above can only
# mirror it. Guard the shape of the real construction directly: headers must be
# built by Email::MIME->create, never by parsing a block of interpolated text.
my $whine_pl = do {
  open my $fh, '<', 'whine.pl' or die "whine.pl: $!";
  local $/ = undef;
  <$fh>;
};
like(
  $whine_pl,
  qr/Email::MIME->create\(\s*header_str/,
  'whine.pl builds mail headers with header_str'
);
unlike($whine_pl, qr/Email::MIME->new\(/,
  'whine.pl does not parse interpolated header text');

# clean_text collapses control characters rather than dropping content.
is(clean_text("a\r\nb"),            'a b',     'CRLF collapsed to a space');
is(clean_text('a' . chr(11) . 'b'), 'a b',     'vertical tab collapsed');
is(clean_text('a' . chr(0) . 'b'),  'a b',     'NUL collapsed');
is(clean_text('  spaced  '),        'spaced',  'whitespace trimmed');
is(clean_text('Nightly bugs'), 'Nightly bugs', 'benign subject unchanged');
is(clean_text(''),             '',             'empty subject stays empty');

done_testing();
