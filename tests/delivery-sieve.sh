#!/bin/sh
# Exercise the global delivery rule with the same sieve-test binary as Dovecot.
set -eu

config=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/home/Maildir"
cp "$2" "$work/delivery-rules.sieve"
script=$work/delivery-rules.sieve
chown -R 5000:5000 "$work"

check_folder() {
    expected=$1
    sieve-test -c "$config" -o "mail_home=$work/home" "$script" "$work/message.eml" >"$work/result" 2>&1 || {
        cat "$work/result"
        exit 1
    }
    if ! grep -Fq " * store message in folder: $expected" "$work/result"; then
        cat "$work/result"
        echo "Expected delivery to $expected" >&2
        exit 1
    fi
    if grep -F ' * store message in folder:' "$work/result" | grep -Fvq " * store message in folder: $expected"; then
        cat "$work/result"
        echo "Unexpected second delivery" >&2
        exit 1
    fi
}

cat >"$work/message.eml" <<'MAIL'
To: user@example.org
From: sender@example.net
Subject: marked spam
X-Spam: Yes

Spam body.
MAIL
check_folder INBOX.Junk

cat >"$work/message.eml" <<'MAIL'
To: user@example.org
From: sender@example.net
Subject: fetched spam
X-Deliver-To-Folder: INBOX.Archive
X-Spam: Yes

Spam body.
MAIL
check_folder INBOX.Junk
if grep -Fq ' * store message in folder: INBOX.Archive' "$work/result"; then
    cat "$work/result"
    echo 'Fetched spam also landed in Archive' >&2
    exit 1
fi

cat >"$work/message.eml" <<'MAIL'
To: user@example.org
From: sender@example.net
Subject: fetched normal mail
X-Deliver-To-Folder: INBOX.Archive
X-Spam: No

Normal body.
MAIL
check_folder INBOX.Archive

cat >"$work/message.eml" <<'MAIL'
To: user@example.org
From: sender@example.net
Subject: normal mail
X-Spam-Status: Yes, score=14.00

Normal body.
MAIL
check_folder INBOX

echo 'Global Sieve delivery cases passed'
