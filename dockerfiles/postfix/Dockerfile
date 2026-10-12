FROM docker.io/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache \
    postfix \
    postfix-ldap \
    postfix-pcre \
    postfix-pgsql \
    ca-certificates \
    tzdata && \
    # Create postfix spool directories
    { postfix set-permissions || true; }

EXPOSE 25 465 587

COPY --chmod=0755 postfix/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 shared/stage-certs.sh /usr/local/bin/stage-certs

ENTRYPOINT ["/entrypoint.sh"]
