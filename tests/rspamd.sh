#!/bin/sh
# Inside the rspamd image: the rendered overrides where mail-rspamd.container
# mounts them, the whole include chain parsed, and the effective RBL setup
# compared with what metrics.conf asks for.
set -eu
cp -a /work/config/rspamd/. /etc/rspamd/local.d/
rspamadm configtest -c /etc/rspamd/rspamd.conf
sh /stack/tests/rbl-expectations.sh
