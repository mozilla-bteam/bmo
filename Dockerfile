
# Regenerate the third-party front-end libraries (jQuery, Prism, mermaid, ...)
# from the versions pinned in package-lock.json. Node lives only in this stage;
# the runtime image stays Node-free.
FROM node:20-slim AS assets

WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY scripts/build-frontend.mjs ./scripts/build-frontend.mjs
COPY js ./js
# Rebuild, then fail the image build if the committed files were stale.
RUN npm run build && npm run verify

FROM us-docker.pkg.dev/moz-fx-bugzilla-prod/bugzilla-prod/bmo-perl-slim:20260721 AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG GITHUB_SHA
ARG GITHUB_SERVER_URL
ARG GITHUB_RUN_ID

ENV GITHUB_SHA=${GITHUB_SHA}
ENV GITHUB_RUN_URL=${GITHUB_SERVER_URL}/mozilla-bteam/bmo/actions/runs/${GITHUB_RUN_ID}

# we run a loopback logging server on this TCP port.
ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf
ENV LOGGING_PORT=5880
ENV LOCALCONFIG_ENV=1

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y rsync curl libcmark-gfm-dev libcmark-gfm-extensions-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . /app

# Overlay the freshly-built third-party front-end libraries so the image always
# matches package-lock.json even if the committed copies drift.
COPY --from=assets /build/js /app/js

RUN chown -R app:app /app && \
    perl -I/app -I/app/local/lib/perl5 -c -E 'use Bugzilla; BEGIN { Bugzilla->extensions }' && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE 8000

HEALTHCHECK CMD curl -sfk http://localhost -o/dev/null

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]

FROM base AS test

HEALTHCHECK NONE

USER root

RUN apt-get update \
    && apt-get install -y firefox-esr lsof \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L https://github.com/mozilla/geckodriver/releases/download/v0.33.0/geckodriver-v0.33.0-linux64.tar.gz -o /tmp/geckodriver.tar.gz \
  && cd /tmp \
  && tar zxvf geckodriver.tar.gz \
  && mv geckodriver /usr/bin/geckodriver

USER app
