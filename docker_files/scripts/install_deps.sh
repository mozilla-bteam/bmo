#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm -l local --quiet"

# - Crypt::SMIME > 0.15 fails to build properly on RHEL6
# - Test::WWW::Selenium for UI testing support
# - Cache::Memcached is not picked up by normal dep check (will investigate)
$CPANM --notest Crypt::SMIME@0.15 \
                Test::WWW::Selenium \
                Cache::Memcached

# - Newer version of Apache2::SizeLimit that what is included in RHEL6
$CPANM --reinstall Apache2::SizeLimit

$CPANM --installdeps --skip-satisfied --with-all-features --without-feature elasticsearch \
        --without-feature oracle --without-feature sqlite --without-feature pg .

# Building documentation
scl enable python27 "pip install -q reportlab rst2pdf sphinx"

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
