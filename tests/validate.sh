#!/bin/sh
# validate.sh <image> <local ref> — this stack's checks of one built image.
# build-image.yml runs it on each architecture before the candidate is
# pushed, so an image that fails here never reaches the registry.
#
# The config is rendered from vars.example.toml with placeholder secrets,
# then checked by the daemon's own parser inside the image itself: a new
# Alpine package that rejects our config fails here, not on a host.
set -eu
image=$1 ref=$2
stack=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

render() {
    git clone --quiet --depth 1 https://github.com/rootless-stack/base "$work/base"
    python3 -m venv "$work/venv"
    "$work/venv/bin/pip" install --quiet --disable-pip-version-check 'jinja2==3.1.6'
    mkdir -p "$work/secrets"
    for s in ldap_readonly_password redis_password; do printf placeholder > "$work/secrets/$s"; done
    "$work/venv/bin/python" "$work/base/render.py" "$stack/config" "$work/config" "$stack/vars.example.toml" "$work/secrets"
}

# The image's entrypoint would start the daemon: the checks run instead,
# as root unless the image's own user is what they need.  No SELinux
# separation for this throwaway container, rather than relabelling the
# checkout it reads.
check() {
    podman run --rm --entrypoint "" --security-opt label=disable \
        -v "$stack:/stack:ro" -v "$work:/work:ro" "$@"
}

case $image in
    postfix)
        render
        check "$ref" sh /stack/tests/postfix.sh ;;
    dovecot)
        render
        check "$ref" sh /stack/tests/dovecot.sh ;;
    rspamd)
        render
        # configtest resolves the upstreams it names; the stack's network
        # does that at runtime.
        check --user root --add-host redis:127.0.0.1 --add-host clamd:127.0.0.1 "$ref" sh /stack/tests/rspamd.sh ;;
    clamd)
        check "$ref" sh /stack/tests/clamd.sh ;;
    postfwd)
        check "$ref" sh /stack/tests/postfwd.sh ;;
    *)
        echo "no checks for $image" >&2
        exit 1 ;;
esac
