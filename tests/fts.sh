#!/bin/sh
# IMAP SEARCH BODY must answer from the flatcurve index.  doveconf accepts
# an fts block whose driver never loads; this APPENDs a message, searches
# its body by word prefix and by an accented word, and checks that the
# index was actually written.  No master here, so no indexer service:
# autoindex is off and `doveadm index` builds the index inline (the
# command the backfill uses too).  Run as root in a throwaway container.
set -eu

config=$1
imap=/usr/libexec/dovecot/imap
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/home"
chown -R 5000:5000 "$work"

session() {
    printf '%s\r\nz LOGOUT\r\n' "$1" | su vmail -s /bin/sh -c \
        "USER=probe@example.org HOME=$work/home $imap -c $config \
         -o mail_home=$work/home -o fts_autoindex=no" >"$work/out" 2>&1 || {
        cat "$work/out"
        exit 1
    }
    if grep -Eq '^[a-y] (NO|BAD)|Fatal|Error' "$work/out"; then
        cat "$work/out"
        exit 1
    fi
}

msg='From: sender@example.net
Subject: fts probe

Die Rechnung kommt mit Ärger.'
session "a APPEND INBOX {$(printf '%s' "$msg" | wc -c | tr -d ' ')+}
$msg"
su vmail -s /bin/sh -c \
    "doveadm -c $config -o mail_home=$work/home index --no-userdb-lookup INBOX"

expect() {
    session "a SELECT INBOX
b SEARCH BODY $1"
    if ! tr -d '\r' <"$work/out" | grep -qx "\* SEARCH${2:+ $2}"; then
        cat "$work/out"
        echo "SEARCH BODY $1: expected '$2'" >&2
        exit 1
    fi
}

expect rechn 1   # word prefix
expect arger 1   # ICU folds Ä
expect zebra ''
expect nung ''   # mid-word: only a read-every-message search finds it

find "$work/home" -type d -name 'fts-flatcurve' | grep -q . || {
    find "$work/home"
    echo 'no fts-flatcurve index written' >&2
    exit 1
}

echo 'Full-text search passed'
