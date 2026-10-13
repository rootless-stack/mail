#!/bin/sh
# rbl-expectations.sh — run INSIDE the rspamd image, with the rendered
# config already in /etc/rspamd/local.d/ (tests/rspamd.sh, right after
# `rspamadm configtest`).
#
# Several of our blocklists are supplied by rspamd's own modules.d/rbl.conf —
# zen.spamhaus.org, bl.blocklist.de, rep.mailspike.net and the Spam Eating
# Monkey pair — and local.d/rbl.conf deliberately does NOT redeclare them:
# a second declaration queries the same zone twice and scores one listing
# under two symbols.  We only override their WEIGHTS in local.d/metrics.conf.
#
# That arrangement has three silent failure modes on an rspamd upgrade:
#
#   * upstream drops a zone       -> a blocklist quietly disappears;
#   * upstream renames a symbol   -> our weight override targets a symbol
#                                    that no longer exists and the stock
#                                    weight silently applies instead;
#   * someone redeclares a zone   -> it is queried twice and double-scored.
#
# So assert the EFFECTIVE config rather than trusting any of it.  Weights are
# read back out of local.d/metrics.conf, never hardcoded here, so this stays
# correct when the scoring is retuned - it only checks that what we asked for
# is what rspamd ended up with.
set -eu

CONFDIR="${CONFDIR:-/etc/rspamd}"
LOCALD="$CONFDIR/local.d"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Zones that must be active, whoever declares them.  Ours come from
# local.d/rbl.conf, the rest from rspamd's defaults; the point of the check is
# that this list does not care which, only that each is present exactly once.
REQUIRED_ZONES="
zen.spamhaus.org
dbl.spamhaus.org
bl.blocklist.de
rep.mailspike.net
bl.spameatingmonkey.net
bl.ipv6.spameatingmonkey.net
bl.spamcop.net
psbl.surriel.com
"

# Our image ships /etc/rspamd/rspamd.conf (CI's configtest names it
# explicitly); the upstream image assembles config elsewhere and rspamadm
# finds it on its own.  Pass -c only when that file is actually there.
if [ -f "$CONFDIR/rspamd.conf" ]; then
    set -- -c "$CONFDIR/rspamd.conf"
else
    set --
fi

rspamadm configdump "$@" rbl > "$work/rbl.dump"
rspamadm configdump "$@" -d > "$work/sym.dump"

rc=0

# Zones of the ENABLED rbl blocks, one per line.  Walks `rbls { ... }` by
# brace depth rather than grepping for the zone string: rspamd ships blocks
# that are declared but switched off (SPAMHAUS_ZEN_URIBL carries the same
# zen.spamhaus.org zone with `enabled = false`), and counting those would
# report a duplicate that does not exist.
awk '
    !in_rbls && /^rbls[[:space:]]*\{/ { in_rbls = 1; depth = 1; next }
    in_rbls {
        if (depth == 1 && $2 == "{") { name = $1; zone = ""; on = 1 }
        if (depth >= 2 && $1 == "rbl")     { z = $3; gsub(/[";]/, "", z); zone = z }
        if (depth >= 2 && $1 == "enabled" && $0 ~ /false/) { on = 0 }

        o = gsub(/\{/, "{"); c = gsub(/\}/, "}"); depth += o - c

        if (depth == 1 && name != "") {
            if (on && zone != "") print zone
            name = ""; zone = ""
        }
        if (depth <= 0) { in_rbls = 0 }
    }
' "$work/rbl.dump" > "$work/zones"

for zone in $REQUIRED_ZONES; do
    n=$(grep -c "^$zone$" "$work/zones" || true)
    case "$n" in
        1) ;;
        0) echo "FAIL: zone $zone is not active in the effective config (upstream dropped or disabled it?)" >&2
           rc=1 ;;
        *) echo "FAIL: zone $zone is declared $n times - it is queried and scored twice" >&2
           rc=1 ;;
    esac
done

# symbol -> weight, as local.d/metrics.conf asks for it
awk '
    /^group "rbl"/            { in_group = 1; next }
    in_group && /^}/          { in_group = 0 }
    in_group && /^[[:space:]]*symbol "/ { sym = $2; gsub(/"/, "", sym); next }
    in_group && /^[[:space:]]*weight[[:space:]]*=/ {
        if (sym != "") { w = $3; sub(/;$/, "", w); print sym, w + 0; sym = "" }
    }
' "$LOCALD/metrics.conf" > "$work/want"

# symbol -> score, as rspamd actually resolved it.  Only symbols a module
# really registers count: a `type =` field marks those.  A weight written in
# metrics.conf for a name no module produces - the exact shape of an upstream
# rename - still shows up here with our score and a description, but with no
# type, so requiring it is what makes this check catch renames at all.
awk '
    depth == 0 && /^[[:space:]]*[A-Z0-9_]+[[:space:]]*\{$/ {
        sym = $1; score = ""; has_type = 0; depth = 1; next
    }
    depth > 0 {
        if (depth == 1 && $1 == "score") { s = $3; sub(/;$/, "", s); score = s }
        if (depth == 1 && $1 == "type")  { has_type = 1 }

        o = gsub(/\{/, "{"); c = gsub(/\}/, "}"); depth += o - c

        if (depth == 0 && sym != "") {
            if (score != "" && has_type) print sym, score + 0
            sym = ""
        }
    }
' "$work/sym.dump" > "$work/got"

while read -r sym want; do
    [ -n "$sym" ] || continue
    got=$(awk -v s="$sym" '$1 == s { print $2; exit }' "$work/got")
    if [ -z "$got" ]; then
        echo "FAIL: $sym is weighted in metrics.conf but no module produces it (renamed upstream?)" >&2
        rc=1
    elif [ "$got" != "$want" ]; then
        echo "FAIL: $sym effective score $got, metrics.conf asks for $want" >&2
        rc=1
    fi
done < "$work/want"

if [ "$rc" -eq 0 ]; then
    echo "rbl expectations OK: $(grep -c . "$work/want") weights, $(echo "$REQUIRED_ZONES" | grep -c .) zones"
fi
exit "$rc"
