#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm -l local --quiet --skip-satisfied"

# - Image::Magick > 6.77 fails to build properly on RHEL6
# - Crypt::SMIME > 0.15 fails to build properly on RHEL6
# - Test::WWW::Selenium for UI testing support
# - Newer version of Apache2::SizeLimit that what is included in RHEL6
$CPANM --notest Image::Magick@6.77 \
                Crypt::SMIME@0.15 \
                Test::WWW::Selenium \
                Cache::Memcached \
                Apache2::SizeLimit

$CPANM --installdeps --with-all-features --without-feature elasticsearch \
        --without-feature oracle --without-feature sqlite --without-feature pg .

# Building documentation
scl enable python27 "pip install -q reportlab rst2pdf sphinx"

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
