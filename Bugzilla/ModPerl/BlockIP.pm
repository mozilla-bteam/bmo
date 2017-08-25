package Bugzilla::ModPerl::BlockIP;
use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::Connection ();

use Apache2::Const -compile => qw(AUTH_REQUIRED OK);

sub handler {
    my $r = shift;
    my $ip = $r->headers_in->{'X-Forwarded-For'} // $r->connection->remote_ip;

    return $ip eq '96.58.158.18'
        ? Apache2::Const::DONE
        : Apache2::Const::OK;
}

1;
