FROM mozillabteam/bmo-slim:20170927.1

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_NUM

ENV CI=${CI}
ENV CIRCLE_BUILD_NUM=${CIRCLE_BUILD_NUM}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV BUNDLE=https://s3.amazonaws.com/moz-devservices-bmocartons/bmo/vendor.tar.gz
ENV PORT=8000

WORKDIR /app
COPY . .

RUN mv /opt/bmo/local /app && \
    chown -R app:app /app && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE $PORT

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
