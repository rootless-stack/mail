#!/bin/sh
# stage-certs.sh — copy the certificate into a tmpfs path that the
# daemon's unprivileged workers can read.
#
# /etc/ssl/mail is the stack user's ~/certs, read-only.  PID 1 (container
# root = the host user) can read it; the workers postfix and dovecot drop
# to cannot.  Runs at container start and from mail-certs.service after a
# renewal: a bare reload re-reads this copy, not the mount.
set -e
DAEMON="${1:?expected postfix or dovecot}"
case "$DAEMON" in postfix|dovecot) ;; *) exit 2 ;; esac
LE_LIVE=/etc/ssl/mail
CERT_OUT="/tmp/${DAEMON}-cert"

if [ ! -r "${LE_LIVE}/fullchain.pem" ]; then
    echo "[stage-certs] WARNING: ${LE_LIVE}/fullchain.pem not readable, skipping cert stage" >&2
    exit 0
fi
mkdir -p "$CERT_OUT"
# Write to temp names then rename, so a reload can never observe a
# half-written key.
for f in fullchain privkey; do
    cp -L "${LE_LIVE}/$f.pem" "$CERT_OUT/.$f.pem.new"
done
chown root:"$DAEMON" "$CERT_OUT"/.*.pem.new
chmod 0644 "$CERT_OUT/.fullchain.pem.new"
chmod 0640 "$CERT_OUT/.privkey.pem.new"   # daemon group can read
for f in fullchain privkey; do
    mv -f "$CERT_OUT/.$f.pem.new" "$CERT_OUT/$f.pem"
done
chown root:"$DAEMON" "$CERT_OUT"
chmod 0750 "$CERT_OUT"
echo "[stage-certs] staged ${LE_LIVE} → $CERT_OUT"
