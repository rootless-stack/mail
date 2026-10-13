#!/bin/sh
# Inside the postfix image: the rendered config where mail-postfix.container
# mounts it, parsed by postfix itself.
set -eu
export MAIL_CONFIG=/etc/postfix/stack
mkdir -p "$MAIL_CONFIG" && cp -a /work/config/postfix/. "$MAIL_CONFIG/"
# -nf parses main.cf, -Mf master.cf; both exit non-zero on a parse error.
postconf -nf >/dev/null
postconf -Mf >/dev/null

# postconf never reads the tables main.cf points at.  `postmap -q ''`
# parses one; its exit code says nothing (1 for "no match" too), so any
# stderr fails.
for f in "$MAIL_CONFIG/header_checks" "$MAIL_CONFIG/mime_header_checks" "$MAIL_CONFIG/regexp_aliases"; do
    [ -e "$f" ] || continue
    echo "[postmap regexp] $f"
    err=$(postmap -q "" "regexp:$f" 2>&1 >/dev/null) || true
    [ -z "$err" ] || { echo "$err" >&2; exit 1; }
done

# The internal routing header (delivery-rules.sieve) never survives SMTP
# ingress: any case, space before the colon, folded value.
for h in 'X-Deliver-To-Folder: INBOX.Trash' 'x-deliver-to-folder: INBOX.Trash' \
         'X-DELIVER-TO-FOLDER :INBOX.Trash' "$(printf 'X-Deliver-To-Folder:\n\tINBOX.Trash')"; do
    [ "$(postmap -q "$h" "pcre:$MAIL_CONFIG/header_checks")" = IGNORE ] || {
        echo "header_checks keeps: $h" >&2; exit 1; }
done
[ -z "$(postmap -q 'X-Deliver-To-Folderx: a' "pcre:$MAIL_CONFIG/header_checks")" ]

# LDAP maps: `postmap -q` parses the .cf, then fails to reach lldap, which
# is expected here.  Only a parse error fails.
for f in "$MAIL_CONFIG"/ldap-*.cf; do
    echo "[postmap ldap] $f"
    out=$(postmap -q test@example.org "ldap:$f" 2>&1 || true)
    if echo "$out" | grep -qE 'missing .* parameter|unknown parameter|syntax error|bad parameter'; then
        echo "$out" >&2
        exit 1
    fi
done
echo 'postfix config passed'
