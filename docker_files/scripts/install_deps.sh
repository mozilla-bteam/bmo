#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

cd $BUGZILLA_ROOT

# Perl dependencies
CPANM="cpanm -l local --quiet --notest"

# Install vendor tarball first
if [ ! -d $BUGZILLA_ROOT/local ]; then
  if [ ! -f /files/vendor.tar.gz ]; then
    wget https://s3.amazonaws.com/moz-devservices-bmocartons/scl3-prod/vendor.tar.gz -O /files/vendor.tar.gz
  fi
  tar zxvf /files/vendor.tar.gz
  perl vendor/bin/carton install --cached --deployment
fi

# Newer version of Apache2::SizeLimit that what is included in RHEL6
$CPANM --reinstall Apache2::SizeLimit

# Pick up any new deps since last time we built this image
$CPANM --skip-satisfied --installdeps --with-all-features \
    --without-feature auth_ldap \
    --without-feature auth_radius \
    --without-feature elasticsearch \
    --without-feature inbound_email \
    --without-feature moving \
    --without-feature oracle \
    --without-feature pg \
    --without-feature psgi \
    --without-feature smtp_auth \
    --without-feature sqlite \
    --without-feature update \
    .

# Test::WWW::Selenium for UI testing support
# Cache::Memcached is not picked up by normal dep check (will investigate)
# Crypt::SMIME > 0.15 fails to build properly on RHEL6
$CPANM --skip-satisfied Test::WWW::Selenium Cache::Memcached Crypt::SMIME@0.15

# Building documentation
scl enable python27 "pip install -q reportlab rst2pdf sphinx"

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
