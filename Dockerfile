FROM mozillabteam/bmo-slim:20171228.1

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV HTTPD_StartServers=8
ENV HTTPD_MinSpareServers=5
ENV HTTPD_MaxSpareServers=20
ENV HTTPD_ServerLimit=256
ENV HTTPD_MaxClients=256
ENV HTTPD_MaxRequestsPerChild=4000
ENV PORT=8000

RUN yum install -y unzip nc
RUN curl -L https://github.com/trivago/gollum/releases/download/v0.5.1/gollum-0.5.1-Linux_x64.zip -o gollum.zip && \
    unzip -o gollum.zip && \
    rm gollum.zip && \
    chmod 0755 gollum && \
    mv gollum /usr/local/bin

WORKDIR /app
COPY . .

RUN mv /opt/bmo/local /app && \
    chown -R app:app /app && \
    perl -c /app/scripts/entrypoint.pl && \
    setcap 'cap_net_bind_service=+ep' /usr/sbin/httpd


USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE $PORT

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
