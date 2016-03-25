#!/bin/bash

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm --quiet --notest --skip-satisfied"

# Force version due to problem with CentOS ImageMagick-devel
# Also work around some other dependency issues
$CPANM Image::Magick@6.77 HTTP::Tiny HTML::Element

perl checksetup.pl --cpanfile
$CPANM --installdeps --with-recommends --with-all-features --without-feature elasticsearch \
       --without-feature oracle --without-feature sqlite --without-feature pg .

# These are not picked up by cpanm --with-all-features for some reason
$CPANM Apache2::SizeLimit
$CPANM XMLRPC::Lite

# For testing support
$CPANM File::Copy::Recursive
$CPANM Test::WWW::Selenium
$CPANM Pod::Coverage
$CPANM Pod::Checker

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
