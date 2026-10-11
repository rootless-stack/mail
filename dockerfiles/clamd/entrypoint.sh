#!/bin/sh
# Boot order:
#   1. Render fangfrisch.conf from the /run/secrets/* mounts (no secrets
#      baked into the image or passed through the environment).
#   2. If signatures are missing, prime them with `freshclam --foreground`.
#      freshclam's NotifyClamd is enabled but clamd isn't up yet on cold boot;
#      we suppress the connect failure with `|| true`.
#   3. Run one fangfrisch refresh pass for third-party feeds, before clamd
#      starts, so clamd loads them once instead of reloading right after its
#      first load (`on_update_exec = clamdscan --reload` finds no clamd yet;
#      harmless).
#   4. Start clamd in the background, wait for its UNIX socket to appear.
#   5. Now that clamd is up, start `freshclam -d` (daemon) so the official
#      CVDs get refreshed every hour (Checks=24) for the life of the container.
#   6. Refresh the third-party feeds again every 65-75 minutes in the
#      background; each update reloads clamd (on_update_exec).
#   7. Bring clamd to the foreground (`wait` on its PID) so the container's
#      lifetime is bound to clamd, not to the boot script.
set -e

CLAMD_SOCKET=/run/clamav/clamd.ctl

# ── Write fangfrisch config from the secret files ───────────────────────────
SECURITEINFO_CUSTOMER_ID=$(cat /run/secrets/securiteinfo_customer_id 2>/dev/null || true)
MALWAREPATROL_RECEIPT=$(cat /run/secrets/malwarepatrol_receipt 2>/dev/null || true)
if [ -z "${SECURITEINFO_CUSTOMER_ID:-}" ]; then
    echo "WARNING: SECURITEINFO_CUSTOMER_ID not set — SecuriteInfo signatures disabled"
    SECURITEINFO_ENABLED=no
else
    SECURITEINFO_ENABLED=yes
fi

# Malwarepatrol stays disabled by default — feed has been broken multiple times;
# operator must consciously enable.
MALWAREPATROL_ENABLED=no

cat > /etc/fangfrisch/fangfrisch.conf <<EOF
[DEFAULT]
db_url           = sqlite:////var/lib/fangfrisch/db.sqlite
local_directory  = /var/lib/clamav
max_size         = 20MB
on_update_exec   = clamdscan --reload
on_update_timeout = 42

[securiteinfo]
enabled     = ${SECURITEINFO_ENABLED}
interval    = 1h
max_size    = 30MB
customer_id = ${SECURITEINFO_CUSTOMER_ID:-}
# On top of fangfrisch's defaults, from what the subscription offers:
# zero-hour malware and Windows executable section hashes.  Not taken:
# securiteinfoold.hdb (large, malware no longer in circulation),
# securiteinfo.pdb/.wdb (link phishing in message bodies, which rspamd
# never sends: antivirus.conf scan_text_mime), the PUA .ndb and spam_marketing
# (a ClamAV hit rejects the mail; unwanted software and spam are not
# viruses), securiteinfo.yara.
url_0hour            = \${prefix}securiteinfo0hour.hdb
url_securiteinfo_mdb = \${prefix}securiteinfo.mdb
url_spam_marketing   = disabled

[malwarepatrol]
enabled  = ${MALWAREPATROL_ENABLED}
interval = 1d
receipt  = ${MALWAREPATROL_RECEIPT:-}

[sanesecurity]
enabled  = no
interval = 2h

[urlhaus]
enabled  = no
interval = 1h
EOF

# ── Initialise fangfrisch DB (idempotent) ────────────────────────────────────
fangfrisch --conf /etc/fangfrisch/fangfrisch.conf initdb 2>/dev/null || true

# ── Prime official signatures if absent (no clamd needed for download) ───────
if [ ! -f /var/lib/clamav/main.cvd ] && [ ! -f /var/lib/clamav/main.cld ]; then
    echo "ClamAV: downloading initial database..."
    # `|| true`: freshclam may attempt NotifyClamd post-update; ignore connect
    # errors during boot (clamd isn't running yet).
    freshclam || true
fi

# ── Refresh third-party signatures before clamd loads them ──────────────────
# Failures are non-fatal: clamd starts with whatever is on disk.  A feed
# disabled above leaves its last download behind, which clamd would keep
# loading.
rm -f /var/lib/clamav/spam_marketing.ndb
if [ "${SECURITEINFO_ENABLED}" = "yes" ]; then
    echo "Fangfrisch: refreshing third-party signatures..."
    fangfrisch --conf /etc/fangfrisch/fangfrisch.conf refresh \
        || echo "WARNING: fangfrisch refresh failed (will retry on next restart)"
fi

# ── Start clamd in the background ────────────────────────────────────────────
echo "ClamAV: starting clamd..."
clamd --foreground &
CLAMD_PID=$!
# This script is PID 1, which ignores SIGTERM without a handler: hand it to
# clamd, or `podman stop` waits out its timeout and SIGKILLs the container.
trap 'kill -TERM "$CLAMD_PID" 2>/dev/null' TERM INT

# Wait for clamd to start accepting connections (LocalSocket appears on disk
# only once clamd is ready). 60-second budget is generous; on cold boot
# signature loading takes ~10–30s.
echo "ClamAV: waiting for clamd socket..."
i=0
while [ ! -S "$CLAMD_SOCKET" ]; do
    if ! kill -0 "$CLAMD_PID" 2>/dev/null; then
        echo "ERROR: clamd exited before becoming ready" >&2
        exit 1
    fi
    i=$((i + 1))
    if [ "$i" -gt 120 ]; then
        echo "ERROR: clamd did not start within 60s" >&2
        kill "$CLAMD_PID" 2>/dev/null || true
        exit 1
    fi
    sleep 0.5
done

# Confirm clamd answers ping (extra defence against half-initialised state).
if ! clamdscan --ping 5 >/dev/null 2>&1; then
    echo "WARNING: clamd socket exists but ping failed; proceeding anyway"
fi
echo "ClamAV: clamd is ready."

# ── Start freshclam as a daemon so official CVDs stay fresh ──────────────────
# `Checks 24` in freshclam.conf → 24 update attempts per day.  `NotifyClamd`
# reloads the running clamd over its LocalSocket after each successful update,
# so we don't depend on container restarts to pick up new signatures.
# `-d` forks into the background; the child reparents to PID 1 (= this script
# via `wait`).  No PID to wait on directly — we rely on clamd being the
# foreground process; if freshclam dies it'll be restarted on the next
# container restart (acceptable: clamd stays up serving stale-but-loaded sigs).
echo "ClamAV: starting freshclam daemon..."
freshclam -d || echo "WARNING: freshclam -d failed to start (signatures will go stale until next restart)"

# ── Refresh third-party signatures every 65-75 minutes ───────────────────────
# SecuriteInfo refuses downloads less than an hour apart; the random spread
# keeps us off the top of the hour.  fangfrisch's own `interval = 1h`
# (its state in /var/lib/fangfrisch survives restarts) skips a feed fetched
# less than an hour ago, so a restart right after a refresh is safe too.
if [ "${SECURITEINFO_ENABLED}" = "yes" ]; then
    (
        while sleep "$(shuf -i 3900-4500 -n 1)"; do
            fangfrisch --conf /etc/fangfrisch/fangfrisch.conf refresh \
                || echo "WARNING: fangfrisch refresh failed (will retry next cycle)"
        done
    ) &
fi

# Foreground: container exits when clamd does.  A trapped signal ends the
# first wait early (status > 128); the second collects clamd's own status.
rc=0
wait "$CLAMD_PID" || rc=$?
if [ "$rc" -gt 128 ] && kill -0 "$CLAMD_PID" 2>/dev/null; then
    rc=0
    wait "$CLAMD_PID" || rc=$?
fi
exit "$rc"
