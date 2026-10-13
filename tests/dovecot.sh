#!/bin/sh
# Inside the dovecot image: the rendered config at /etc/dovecot, parsed by
# dovecot, every Sieve script compiled, and the runtime paths doveconf
# cannot judge exercised (delivery rules, personal Sieve storage,
# imapsieve learning, full-text search).
set -eu
cp -a /work/config/dovecot/. /etc/dovecot/
doveconf -n >/dev/null
# sievec without -c knows only a minimal extension set (no fileinto,
# variables); with our config it compiles as lmtp would.
for s in /etc/dovecot/sieve/*.sieve; do
    echo "[sievec] $s"
    sievec -c /etc/dovecot/dovecot.conf "$s"
done
sh /stack/tests/delivery-sieve.sh /etc/dovecot/dovecot.conf /etc/dovecot/sieve/delivery-rules.sieve

# doveconf accepts any sieve_script type and path; a wrong one only fails
# at first use.  put + activate + list as vmail against a scratch home.
# The probes run as vmail, so open up this throwaway copy.
chmod -R a+rX /etc/dovecot
mkdir -p /tmp/sieve-probe && chown vmail:vmail /tmp/sieve-probe
echo 'keep;' >/tmp/probe.sieve && chmod 644 /tmp/probe.sieve
# shellcheck disable=SC2016  # expanded by vmail's shell
su vmail -s /bin/sh -c '
    d="doveadm -o mail_home=/tmp/sieve-probe"
    $d sieve put --no-userdb-lookup probe < /tmp/probe.sieve &&
    $d sieve activate --no-userdb-lookup probe &&
    $d sieve list --no-userdb-lookup | grep -q "^probe ACTIVE$"' ||
    { echo "personal sieve storage unusable: check sieve_script personal {} in 90-plugin.conf" >&2; exit 1; }

sh /stack/tests/imapsieve.sh /etc/dovecot/dovecot.conf
sh /stack/tests/fts.sh /etc/dovecot/dovecot.conf
echo 'dovecot config passed'
