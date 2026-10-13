#!/bin/sh
set -e

# /var/spool/postfix is a host bind-mount.  In rootless podman, files
# created by in-container postfix-user (UID 100) and in-container root
# (UID 0) map to *different* host UIDs (a subuid vs. mail-svc), so
# perms drift across container restarts and `postfix check` fails with
# "Permission denied" on subdirs whose owner the new container can't
# read.  We can't use `postfix set-permissions` because it also walks
# /etc/postfix which is :ro, so it errors with "Read-only file system".
# Instead, set the canonical postfix queue layout ourselves — the modes
# match what `postfix-files` (the package manifest) declares, so postfix
# stops emitting "not owned by root" / "not owned by group postdrop"
# warnings during start-fg.
#
# Layout (from postfix-files):
#   /var/spool/postfix         root:root    0755
#   /var/spool/postfix/pid     root:root    0755
#   /var/spool/postfix/public  postfix:postdrop 0710  (postdrop sgid)
#   /var/spool/postfix/maildrop postfix:postdrop 0730 (postdrop sgid)
#   {active,incoming,defer,deferred,hold,saved,corrupt,bounce,trace,flush}
#                              postfix:root 0700
#   /var/spool/postfix/private postfix:root 0700
chown root:root          /var/spool/postfix
chmod 0755               /var/spool/postfix

mkdir -p /var/spool/postfix/pid
chown root:root          /var/spool/postfix/pid
chmod 0755               /var/spool/postfix/pid

mkdir -p /var/spool/postfix/public /var/spool/postfix/maildrop
chown postfix:postdrop   /var/spool/postfix/public /var/spool/postfix/maildrop
chmod 0710               /var/spool/postfix/public
chmod 0730               /var/spool/postfix/maildrop

for d in active incoming defer deferred hold saved corrupt bounce trace flush private; do
    mkdir -p "/var/spool/postfix/$d"
    chown postfix:root   "/var/spool/postfix/$d"
    chmod 0700           "/var/spool/postfix/$d"
done

# A master.cf service named <dir>/<name> (sieve-submit/smtp) takes its
# smtpd lock at pid/unix.<dir>/<name>; without that directory the daemon
# dies at every start and master throttles the service.
postconf -M | awk '$1 ~ "/" {split($1, a, "/"); print "/var/spool/postfix/pid/" $2 "." a[1]}' | xargs -r mkdir -p

# data_directory is a fresh tmpfs (ReadOnly=true): postfix-files wants it
# postfix-owned.  No newaliases: local delivery is off (mydestination is
# empty), and the image's /etc/postfix is read-only.
chown postfix /var/lib/postfix

# Start postfix in foreground
exec postfix start-fg
