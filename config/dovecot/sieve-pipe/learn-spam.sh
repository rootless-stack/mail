#!/bin/sh
# learn-spam.sh — called by Dovecot IMAPSieve when a message lands in Junk
# (move/copy from another folder).  Trains both bayes AND the local fuzzy
# storage worker, so future similar messages score high without manual help.
#
# Receives the full RFC 2822 message on stdin.  Dovecot runs in
# host networking, so the bridge name `rspamd` does not resolve here.
# Talk to its controller over the ACL-gated Unix socket.
#
# Two POSTs because the controller API expects the message body as the
# request body in BOTH calls — we save it to a temp file once and replay
# it twice.

set -eu
MSG=$(mktemp)
trap 'rm -f "$MSG"' EXIT
cat > "$MSG"
SOCK=/run/rootless-ipc/rspamd-controller/controller.sock

# 1. Bayes — corpus learns the message tokens as spam.
curl -sf --unix-socket "$SOCK" --data-binary @"$MSG" http://localhost/learnspam >/dev/null

# 2. Local fuzzy — store a fuzzy hash of the message structure so
#    near-duplicates also fire FUZZY_LOCAL_DENIED.  flag=1 matches the
#    fuzzy_map entry in fuzzy_check.conf.j2; weight=10 is rspamd's
#    canonical "definitely spam" weight (max_score in the map is 12).
curl -sf --unix-socket "$SOCK" --data-binary @"$MSG" \
    "http://localhost/fuzzyadd?flag=1&weight=10" >/dev/null
