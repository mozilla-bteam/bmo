# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Localconfig;
use 5.10.1;
use Moo;
use MooX::StrictConstructor;

use Bugzilla::Install::Localconfig qw(LOCALCONFIG_VARS);

foreach my $var (LOCALCONFIG_VARS) {
  if ($var->{lazy}) {
    has $var->{name} => (is => 'lazy');
  }
  else {
    has $var->{name} => (is => 'ro', required => 1);
  }
}

has 'attachment_host_regex' => (is => 'lazy');
has 'basepath'              => (is => 'lazy');

sub _build_attachment_host_regex {
  my ($base) = @_;
  return undef unless $base;
  my $val = $base;
  $val =~ s{^https?://}{}s;
  $val =~ s{/$}{}s;
  my $regex = quotemeta $val;
  $regex =~ s/\\\%bugid\\\%/\\d+/g;
  return qr/^$regex$/s;
}

# Use the site's URL as the default Canonical URL
sub _build_canonical_urlbase {
  my ($self) = @_;
  $self->urlbase;
}

sub _build_basepath {
  my ($self) = @_;
  my $path = $self->urlbase;
  $path =~ s/^https?:\/\/.*?\//\//;
  return $path;
}


1;
