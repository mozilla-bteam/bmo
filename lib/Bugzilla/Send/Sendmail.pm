# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Send::Sendmail;
use 5.10.1;
use strict;
use warnings;

use base qw(Email::Send::Sendmail);

use Return::Value;
use Symbol qw(gensym);

sub send {
  my ($class, $message, @args) = @_;
  my $mailer = $class->_find_sendmail;

  return failure "Couldn't find 'sendmail' executable in your PATH"
    . " and Email::Send::Sendmail::SENDMAIL is not set"
    unless $mailer;

  return failure "Found $mailer but cannot execute it" unless -x $mailer;

  local $SIG{'CHLD'} = 'DEFAULT';

  my $pipe = gensym;

  open($pipe, '|-', "$mailer -t -oi @args")
    || return failure "Error executing $mailer: $!";
  print($pipe $message->as_string)
    || return failure "Error printing via pipe to $mailer: $!";
  unless (close $pipe) {
    return failure "error when closing pipe to $mailer: $!" if $!;
    my ($error_message, $is_transient) = _map_exitcode($? >> 8);
    if (Bugzilla->get_param_with_override('use_mailer_queue')) {

      # Return success for errors which are fatal so Bugzilla knows to
      # remove them from the queue
      if ($is_transient) {
        return failure "error when closing pipe to $mailer: $error_message";
      }
      else {
        warn "error when closing pipe to $mailer: $error_message\n";
        return success;
      }
    }
    else {
      return failure "error when closing pipe to $mailer: $error_message";
    }
  }
  return success;
}

sub _map_exitcode {

  # Returns (error message, is_transient)
  # from the sendmail source (sendmail/sysexit.h)
  my $code = shift;
  if ($code == 64) {
    return ("Command line usage error (EX_USAGE)", 1);
  }
  elsif ($code == 65) {
    return ("Data format error (EX_DATAERR)", 1);
  }
  elsif ($code == 66) {
    return ("Cannot open input (EX_NOINPUT)", 1);
  }
  elsif ($code == 67) {
    return ("Addressee unknown (EX_NOUSER)", 0);
  }
  elsif ($code == 68) {
    return ("Host name unknown (EX_NOHOST)", 0);
  }
  elsif ($code == 69) {
    return ("Service unavailable (EX_UNAVAILABLE)", 1);
  }
  elsif ($code == 70) {
    return ("Internal software error (EX_SOFTWARE)", 1);
  }
  elsif ($code == 71) {
    return ("System error (EX_OSERR)", 1);
  }
  elsif ($code == 72) {
    return ("Critical OS file missing (EX_OSFILE)", 1);
  }
  elsif ($code == 73) {
    return ("Can't create output file (EX_CANTCREAT)", 1);
  }
  elsif ($code == 74) {
    return ("Input/output error (EX_IOERR)", 1);
  }
  elsif ($code == 75) {
    return ("Temp failure (EX_TEMPFAIL)", 1);
  }
  elsif ($code == 76) {
    return ("Remote error in protocol (EX_PROTOCOL)", 1);
  }
  elsif ($code == 77) {
    return ("Permission denied (EX_NOPERM)", 1);
  }
  elsif ($code == 78) {
    return ("Configuration error (EX_CONFIG)", 1);
  }
  else {
    return ("Unknown Error ($code)", 1);
  }
}

1;

