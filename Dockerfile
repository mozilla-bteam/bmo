FROM mozillabteam/bmo-slim:20170927.1

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
