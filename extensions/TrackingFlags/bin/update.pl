#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use 5.10.1;

use lib qw(. lib local/lib/perl5);

BEGIN {
  use Bugzilla;
  Bugzilla->extensions;
}

use JSON::MaybeXS qw(decode_json);

use constant PD_ENDPOINT => 'https://product-details.mozilla.org/1.0/';
use constant PD_FILES    => qw(firefox_versions thunderbird_versions);

my $ua = LWP::UserAgent->new(timeout => 10);

if (Bugzilla->params->{proxy_url}) {
  $ua->proxy('https', Bugzilla->params->{proxy_url});
}

foreach my $key (PD_FILES) {
  my $response = $ua->get(PD_ENDPOINT . $key . '.json');

  unless ($response->is_error) {
    my $data = decode_json($response->decoded_content);
    Bugzilla->memcached->set_config({key => $key, data => $data});
  }
}
