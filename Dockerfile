FROM perl:5.30.0-slim AS builder

RUN apt-get update
RUN apt-get install -y \
    build-essential curl libssl-dev zlib1g-dev openssl \
    libexpat-dev cmake git libcairo-dev libgd-dev \
    default-libmysqlclient-dev unzip wget
RUN cpanm --notest --quiet App::cpm Module::CPANfile Carton::Snapshot

WORKDIR /app

COPY cpanfile cpanfile.snapshot /app/

RUN cpm install
# secure mail loop fixes
RUN cpm install http://s3.amazonaws.com/moz-devservices-bmocartons/third-party/Crypt-OpenPGP-1.15.tar.gz

RUN apt-get install -y apt-file
RUN apt-file update
RUN find local -name '*.so' -exec ldd {} \; \
    | egrep -v 'not.found|not.a.dynamic.executable' \
    | awk '$3 {print $3}' \
    | sort -u \
    | xargs -IFILE apt-file search -l FILE \
    | sort -u > PACKAGES

FROM perl:5.30.0-slim

ENV DEBIAN_FRONTEND noninteractive

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf

# we run a loopback logging server on this TCP port.
ENV LOGGING_PORT=5880

ENV LOCALCONFIG_ENV=1

WORKDIR /app

COPY --from=builder /app/local /app/local
COPY --from=builder /app/PACKAGES /app/PACKAGES

RUN apt-get update && apt-get upgrade -y && apt-get install -y curl git libcap2-bin xz-utils vim $(cat PACKAGES)

RUN curl -L https://github.com/dylanwh/tocotrienol/releases/download/1.0.6/tct-centos6.tar.xz > /usr/local/bin/tct.tar.xz && \
    tar -C /usr/local/bin -xvf /usr/local/bin/tct.tar.xz && \
    rm /usr/local/bin/tct.tar.xz && \
    chmod +x /usr/local/bin/tct && \
    curl -L https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini > /usr/local/sbin/tini && \
    chmod +x /usr/local/sbin/tini && \
    useradd -u 10001 -U app -m && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/perl

COPY . /app

RUN chown -R app.app /app && \
    perl -I/app -I/app/local/lib/perl5 -c -E 'use Bugzilla; BEGIN { Bugzilla->extensions }' && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE 8000

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
