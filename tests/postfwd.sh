#!/bin/sh
# Inside the postfwd image: the committed rule file, end to end.
# `postfwd3 --showconfig` passes a broken rule, so run the server and check
# the cap itself: 1000 recipients pass, the 1001st is deferred with 450,
# and a healthcheck-shaped request counts nothing.
set -eu
perl -c /usr/local/bin/postfwd-health
# --user/--group as in the image's ENTRYPOINT: the default (nobody) makes
# postfwd chown its socket, which only root may.
postfwd3 --nodaemon --stdout --nodns --user postfwd --group postfwd \
    --proto unix --port /tmp/postfwd.sock \
    --file /stack/config/postfwd/postfwd.cf >/tmp/postfwd.log 2>&1 &
for _ in $(seq 20); do [ -S /tmp/postfwd.sock ] && break; sleep 0.5; done
[ -S /tmp/postfwd.sock ] || { cat /tmp/postfwd.log; echo 'postfwd did not start' >&2; exit 1; }

ask() {  # <protocol_state> <recipient_count> → postfwd's action line
    perl -MIO::Socket::UNIX -e '
        my $s = IO::Socket::UNIX->new(Peer => "/tmp/postfwd.sock") or die "connect: $!\n";
        print $s join("", map { "$_\n" }
            "request=smtpd_access_policy", "protocol_state=$ARGV[0]", "protocol_name=ESMTP",
            "client_address=127.0.0.1", "client_name=localhost", "helo_name=validate",
            "sender=", "recipient=", "recipient_count=$ARGV[1]", "");
        my $l = <$s> // ""; print $l;' "$1" "$2"
}
fail() { cat /tmp/postfwd.log; echo "$1" >&2; exit 1; }
ask VRFY 0 | grep -q '^action=DUNNO' || fail 'healthcheck request not DUNNO'
ask END-OF-MESSAGE 1000 | grep -q '^action=DUNNO' || fail '1000 recipients refused'
ask VRFY 0 | grep -q '^action=DUNNO' || fail 'healthcheck request counted'
ask END-OF-MESSAGE 1 | grep -q '^action=450 ' || fail 'recipient 1001 not deferred'
echo 'postfwd rules passed'
