#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Mailer;
use Bugzilla::Reminder;

use DateTime;
use Email::MIME;
use Sys::Hostname qw(hostname);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

# Find any reminders that are due today or overdue that have not been marked sent
my $today = DateTime->now()->strftime('%Y-%m-%d 00:00:00');

my $reminders
  = Bugzilla::Reminder->match({
  sent => 0, WHERE => {'reminder_ts <= ?' => $today}
  });

foreach my $reminder (@{$reminders}) {
  my $vars = {reminder => $reminder};

  # Check to see if the user can still see the bug. If not,
  # mark sent but do not send the email
  if ($reminder->user->can_see_bug($reminder->bug)) {
    _send_email($reminder->user, {reminder => $reminder});
  }
  else {
    WARN( 'REMINDER: Email not sent since user '
        . $reminder->user->login
        . ' could no longer see bug '
        . $reminder->bug->id);
  }

  $reminder->set_sent(1);
  $reminder->update;
}

sub _send_email {
  my ($user, $vars) = @_;

  my $template = Bugzilla->template_inner($user->setting('lang'));

  my ($header, $text);
  $template->process('email/reminder-header.txt.tmpl', $vars, \$header)
    || ThrowTemplateError($template->error());
  $header .= "\n";
  $template->process('email/reminder.txt.tmpl', $vars, \$text)
    || ThrowTemplateError($template->error());

  my @parts = (Email::MIME->create(
    attributes => {
      content_type => 'text/plain',
      charset      => 'UTF-8',
      encoding     => 'quoted-printable',
    },
    body_str => $text,
  ));

  if ($user->setting('email_format') eq 'html') {
    my $html;
    $template->process('email/reminder.html.tmpl', $vars, \$html)
      || ThrowTemplateError($template->error());
    push @parts,
      Email::MIME->create(
      attributes => {
        content_type => 'text/html',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable',
      },
      body_str => $html,
      );
  }

  my $email = Email::MIME->new($header);
  $email->header_set('X-Generated-By' => hostname());

  if (scalar @parts == 1) {
    $email->content_type_set('text/plain');
  }
  else {
    $email->content_type_set('multipart/alternative');
  }
  $email->parts_set(\@parts);

  MessageToMTA($email);
}
