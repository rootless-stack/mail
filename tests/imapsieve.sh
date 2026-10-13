#!/bin/sh
# Drive real IMAP MOVEs through the imapsieve triggers with stub learn
# scripts.  doveconf accepts filters that never fire at runtime; this
# would have caught both `imap_after` (2026-09-20) and a source gate on the
# always-empty `vnd.dovecot.mailbox-from` (2026-09-28).  Must run as root, in a
# throwaway container: it compiles into the scripts' real bin_path.
set -eu

config=$1
imap=/usr/libexec/dovecot/imap
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/home" "$work/pipe"
for kind in spam ham; do
    printf '#!/bin/sh\ncat >/dev/null\necho %s >>%s/log\n' "$kind" "$work" >"$work/pipe/learn-$kind.sh"
done
chmod 755 "$work/pipe"/*.sh
: >"$work/log"
chown -R 5000:5000 "$work"

session() {
    printf '%s\r\nz LOGOUT\r\n' "$1" | su vmail -s /bin/sh -c \
        "USER=probe@example.org HOME=$work/home $imap -c $config \
         -o mail_home=$work/home -o fts_autoindex=no -o sieve_pipe_bin_dir=$work/pipe" >"$work/out" 2>&1 || {
        cat "$work/out"
        exit 1
    }
    if grep -Eq '^[a-y] (NO|BAD)|Fatal|Error' "$work/out"; then
        cat "$work/out"
        exit 1
    fi
}

move() {
    session "a SELECT $1
b MOVE 1 $2"
    got=$(tr '\n' ' ' <"$work/log")
    if [ "$got" != "$3" ]; then
        cat "$work/out"
        echo "MOVE $1 -> $2: learned '$got', expected '$3'" >&2
        exit 1
    fi
}

msg='From: sender@example.net
Subject: imapsieve probe

Probe body.'
session "a APPEND INBOX {$(printf '%s' "$msg" | wc -c | tr -d ' ')+}
$msg"

move INBOX INBOX.Junk 'spam '
move INBOX.Junk INBOX 'spam ham '
move INBOX INBOX.Junk 'spam ham spam '
move INBOX.Junk INBOX.Trash 'spam ham spam '
move INBOX.Trash INBOX 'spam ham spam '

echo 'IMAPSieve learn triggers passed'
