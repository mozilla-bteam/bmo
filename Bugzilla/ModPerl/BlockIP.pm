package Bugzilla::ModPerl::BlockIP;
use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::Connection ();

use Apache2::Const -compile => qw(OK);

sub handler {
    my $r = shift;
    my $ip = $r->headers_in->{'X-Forwarded-For'} // $r->connection->remote_ip;

    if ($ip eq '96.58.158.18') {
        $r->status_line("429 Too Many Requests");
        $r->custom_response(500, "Too Many Requests");
        return 429;
    }
    else {
        return Apache2::Const::OK;
    }
}

1;
