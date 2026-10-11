FROM docker.io/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache \
    rspamd \
    rspamd-client \
    rspamd-fuzzy \
    curl \
    ca-certificates \
    tzdata && \
    mkdir -p /var/lib/rspamd /run/rspamd && \
    chown -R rspamd:rspamd /var/lib/rspamd /run/rspamd

USER rspamd
CMD ["rspamd", "--no-fork", "-c", "/etc/rspamd/rspamd.conf"]
