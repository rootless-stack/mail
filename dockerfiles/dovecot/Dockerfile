FROM docker.io/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache \
    dovecot \
    dovecot-ldap \
    dovecot-lmtpd \
    dovecot-pgsql \
    dovecot-pigeonhole-plugin \
    dovecot-fts-flatcurve \
    ca-certificates \
    tzdata \
    openssl \
    curl \
    msmtp && \
    # vmail with a fixed uid/gid to match host volume ownership
    addgroup -g 5000 vmail && \
    adduser -u 5000 -G vmail -H -D -s /sbin/nologin vmail && \
    mkdir -p /var/mail/vmail /run/dovecot && \
    chown vmail:vmail /var/mail/vmail && \
    chmod 750 /var/mail/vmail

EXPOSE 993 4190

COPY --chmod=0755 dovecot/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 shared/stage-certs.sh /usr/local/bin/stage-certs

ENTRYPOINT ["/entrypoint.sh"]
