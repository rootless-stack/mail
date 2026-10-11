#!/bin/sh
set -e

# ── Stage TLS material into the container ─────────────────────────────────
# See /usr/local/bin/stage-certs (also run by the host-side cert-reload.sh
# after every renewal, so the copy dovecot reads never goes stale).
/usr/local/bin/stage-certs dovecot

exec dovecot -F
