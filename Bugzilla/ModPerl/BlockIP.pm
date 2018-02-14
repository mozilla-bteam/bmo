# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl::BlockIP;
use 5.10.1;
use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::Connection ();

use Apache2::Const -compile => qw(OK);
use Cache::Memcached::Fast;

use constant BLOCK_TIMEOUT => 60*60;

my $MEMCACHED;
my $STATIC_URI = qr{
    ^/
     (?: extensions/[^/]+/web
       | robots\.txt
       | __heartbeat__
       | __lbheartbeat__
       | __version__
       | images
       | skins
       | js
       | errors
     )
}xms;

sub set_memcached {
    my ($class, $memcached) = @_;
    $MEMCACHED = $memcached;
}

sub block_ip {
    my ($class, $ip) = @_;
    $MEMCACHED->set("block_ip:$ip" => 1, BLOCK_TIMEOUT) if $MEMCACHED;
}

sub unblock_ip {
    my ($class, $ip) = @_;
    $MEMCACHED->delete("block_ip:$ip") if $MEMCACHED;
}

sub handler {
    my $r = shift;
    return Apache2::Const::OK if $r->uri =~ $STATIC_URI;

    my $ip = $r->headers_in->{'X-Forwarded-For'};
    if ($ip) {
        $ip = (split(/\s*,\s*/ms, $ip))[-1];
    }
    else {
        $ip = $r->connection->remote_ip;
    }

    if ($MEMCACHED && $MEMCACHED->get("block_ip:$ip")) {
        __PACKAGE__->block_ip($ip);
        $r->status_line("429 Too Many Requests");
        # 500 is used here because apache 2.2 doesn't understand 429.
        # the above line and the return value together mean we produce 429.
        # Any other variation doesn't work.
        $r->custom_response(500, "Too Many Requests");
        return 429;
    }
    else {
        return Apache2::Const::OK;
    }
}

1;
