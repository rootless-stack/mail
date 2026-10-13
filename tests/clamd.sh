#!/bin/sh
# Inside the clamd image: clamconf parses the baked-in clamd.conf.  It exits
# 0 on problems it forgives, so its ERROR lines decide.
set -eu
clamconf >/tmp/clamconf.out 2>&1 || { cat /tmp/clamconf.out; exit 1; }
if grep -qiE '(^|[^a-z])ERROR' /tmp/clamconf.out; then
    cat /tmp/clamconf.out
    echo 'clamconf reported ERROR' >&2
    exit 1
fi
echo 'clamd config passed'
