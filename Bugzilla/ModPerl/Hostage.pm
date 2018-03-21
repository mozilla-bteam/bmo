package Bugzilla::ModPerl::Hostage;
use 5.10.1;
use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::Connection ();

use Apache2::Const qw(:common); ## no critic (Freenode::ModPerl)
use Cache::Memcached::Fast;

use constant BLOCK_TIMEOUT => 60*60;

sub handler {
    my $r = shift;
    state $urlbase         = Bugzilla->localconfig->{urlbase};
    state $urlbase_uri     = URI->new($urlbase);
    state $urlbase_host    = $urlbase_uri->host;
    state $urlbase_host_regex = qr/^bug(\d+)\.\Q$urlbase_host\E$/;
    state $attachment_base = Bugzilla->localconfig->{attachment_base};
    state $attachment_root = do {
        if ($attachment_base && $attachment_base =~ m{https?://bug\%bug_id\%\.(.+)$}) {
            $1;
        }
    };
    state $attachment_regex = do {
        if ($attachment_base) {
            my $regex = quotemeta $attachment_base;
            $regex =~ s/\\\%bugid\\\%/\\d+/g;
            qr/^$regex$/s;
        }
    };

    my $hostname  = $r->hostname;
    my $path      = $r->uri;

    return OK if $hostname eq $urlbase_host;

    if ($hostname eq $attachment_root) {
        if ($path eq '/hstsping') {
            return OK;
        }
        else {
            $r->headers_out->set(Location => $urlbase);
            return REDIRECT;
        }
    }
    elsif ($hostname =~ $attachment_regex && ! $path =~ m{^/attachment\.cgi}s) {
        my $new_uri = URI->new($r->unparsed_uri);
        $new_uri->scheme($urlbase_uri->scheme);
        $new_uri->host($urlbase_host);
        $r->headers_out->set(Location => $new_uri);
        return REDIRECT;
    }
    elsif (my ($id) = $hostname =~ $urlbase_host_regex) {
        my $new_uri = $urlbase_uri->clone;
        $new_uri->path("/show_bug.cgi?id=$id");
        $r->headers_out->set(Location => $new_uri);
        return REDIRECT;
    }

    return NOT_FOUND;
}

1;
