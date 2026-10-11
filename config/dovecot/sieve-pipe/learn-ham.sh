#!/bin/sh
# learn-ham.sh — called by Dovecot IMAPSieve when a message is moved OUT
# of Junk to anywhere other than Trash (Trash skip is in report-ham.sieve).
#
# The user is saying "this was NOT spam", so we:
#   1. Train bayes: tokens learn as ham.
#   2. Remove any fuzzy hash this message contributed — false-positive
#      correction.  fuzzydel doesn't care about flag/weight; it just
#      deletes any local fuzzy entries whose hash matches the message.

set -eu
MSG=$(mktemp)
trap 'rm -f "$MSG"' EXIT
cat > "$MSG"
SOCK=/run/rootless-ipc/rspamd-controller/controller.sock

curl -sf --unix-socket "$SOCK" --data-binary @"$MSG" http://localhost/learnham >/dev/null
curl -sf --unix-socket "$SOCK" --data-binary @"$MSG" "http://localhost/fuzzydel?flag=1" >/dev/null
