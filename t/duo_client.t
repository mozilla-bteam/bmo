#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

use Capture::Tiny qw(capture);
use Storable      qw(dclone);
use Test::More;
use Try::Tiny;

use Bugzilla;
use Bugzilla::Util qw(generate_random_password);

BEGIN {
  use ok 'Bugzilla::DuoClient';
}

my $params = Bugzilla->params;

my $full_args = {
  host          => 'duo',
  client_id     => 'xxxxxxxxxxxxxxxxxxxx',
  client_secret => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  redirect_uri  => 'http://localhost:8000/mfa/duo/callback',
};

# Failure tests
my $fail_ok = sub {
  my ($expected_error, $code, $args) = @_;
  try {
    $code->(@{$args});
  }
  catch {
    my $got_error = $_;
    $got_error =~ s/\n/ /g;
    ok($got_error =~ /$expected_error/, $expected_error);
  };
};

# no arguments
$fail_ok->(
  'Missing required arguments: client_id, client_secret, host',
  sub {
    my $duo = Bugzilla::DuoClient->new();
  }
);

# missing host
$fail_ok->(
  'Missing required arguments: host',
  sub {
    my $args = dclone($full_args);
    delete $args->{host};
    my $duo = Bugzilla::DuoClient->new($args);
  }
);

# missing client id
$fail_ok->(
  'Missing required arguments: client_id',
  sub {
    my $args = dclone($full_args);
    delete $args->{client_id};
    my $duo = Bugzilla::DuoClient->new($args);
  }
);

# missing client secret
$fail_ok->(
  'Missing required arguments: client_secret',
  sub {
    my $args = dclone($full_args);
    delete $args->{client_secret};
    my $duo = Bugzilla::DuoClient->new($args);
  }
);

# invalid client id
$fail_ok->(
  'The client id is invalid',
  sub {
    my $args = dclone($full_args);
    $args->{client_id} = substr $args->{client_id}, 0, 14;    # truncate to 15 chars
    my $duo = Bugzilla::DuoClient->new($args);
  }
);

# invalid client secret
$fail_ok->(
  'The client secret is invalid',
  sub {
    my $args = dclone($full_args);
    $args->{client_secret} = substr $args->{client_secret}, 0, 34;    # truncate to 35 chars
    my $duo = Bugzilla::DuoClient->new($args);
  }
);

ok(my $duo = Bugzilla::DuoClient->new($full_args), 'Load module OK');

# Emtpy username for create_auth_url
$fail_ok->(
  'The Duo username was invalid',
  sub {
    my $duo = Bugzilla::DuoClient->new($full_args);
    $duo->create_auth_url('', generate_random_password(22));
  }
);

# Invalid state for create_auth_url
$fail_ok->(
  'The Duo state must be at least 22 characters long and no longer than 1024 characters',
  sub {
    my $duo   = Bugzilla::DuoClient->new($full_args);
    my $state = generate_random_password(10);
    $state = substr $state, 0, 15;
    $duo->create_auth_url('admin@mozilla.test', $state);
  }
);

# Valid parameters for create_auth_url
ok($duo->create_auth_url('admin@mozilla.test', generate_random_password(22)),
  'Valid create_auth_url');

# failed health check
$fail_ok->(
  'The Duo service health check failed',
  sub {
    my $duo = Bugzilla::DuoClient->new($full_args);
    $duo->health_check();
  }
);

done_testing;
