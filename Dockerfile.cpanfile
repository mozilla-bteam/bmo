FROM perl:5.44.0-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
    build-essential curl libssl-dev zlib1g-dev openssl \
    libexpat-dev cmake git libcairo-dev libgd-dev \
    default-libmysqlclient-dev unzip wget libgmp-dev

RUN cpanm --notest --quiet App::cpm Module::CPANfile Carton::Snapshot

WORKDIR /app

COPY Makefile.PL Bugzilla.pm gen-cpanfile.pl /app/
COPY extensions/ /app/extensions/

RUN perl Makefile.PL \
    && make cpanfile

# Bug #133363 for Crypt-DES: Crypt::DES fails to build with Xcode 12 [rt.cpan.org #133363]
# https://rt.cpan.org/Public/Bug/Display.html?id=133363
RUN ccflags=$(perl -MConfig -e 'print qq{$Config{ccflags} -Wno-implicit-function-declaration};'); \
    cpanm -L local --notest --quiet --configure-args="ccflags='$ccflags'" Crypt::DES

# Bug #149108 for Net-IDN-Encode: [PATCH] use uvchr_to_utf8_flags instead of uvuni_to_utf8_flags (which is removed in perl 5.38.0)
# https://rt.cpan.org/Public/Bug/Display.html?id=149108
RUN cpanm -L local --notest --quiet --from https://cpan.metacpan.org/ \
    https://cpan.metacpan.org/authors/id/E/ET/ETHER/Net-IDN-Encode-2.501-TRIAL.tar.gz

RUN carton install

