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
    my $hostname  = $r->hostname;
    my $path      = $r->uri;

    return OK if $hostname eq 'bugzilla.mozilla.org';

    if ($hostname eq 'bmoattachments.org') {
        if ($path eq '/hstsping') {
            return OK;
        }
        else {
            $r->headers_out->set(Location => 'https://bugzilla.mozilla.org');
            return REDIRECT;
        }
    }
    elsif ($hostname =~ m{^bug(\d+)\.bmoattachments.org$} && ! $path =~ m{^/attachment\.cgi}s) {
        my $new_uri = URI->new($r->unparsed_uri);
        $new_uri->scheme('');
        $new_uri->host('bugzilla.mozilla.org');
        $r->headers_out->set(Location => $new_uri);
        return REDIRECT;
    }
    elsif (my ($id) = $hostname =~ m{^bug(\d+)\.bugzilla\.mozilla.org$}) {
        my $new_uri = URI->new('https://bugzilla.mozilla.org');
        $new_uri->path("/show_bug.cgi?id=$id");
        $r->headers_out->set(Location => $new_uri);
        return REDIRECT;
    }

    return NOT_FOUND;
}

# FIXME: make this use actual configuration values.
sub _get_config {
    return {
    }
}

1;
