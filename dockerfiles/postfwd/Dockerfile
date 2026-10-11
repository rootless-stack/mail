FROM docker.io/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

# postfwd: the daily outbound cap in front of postfix's submission and
# Sieve listeners (config/postfwd/postfwd.cf).  Alpine's
# package, run as its `postfwd` user (100:101, Pattern A).
RUN apk add --no-cache postfwd tzdata
COPY postfwd-health /usr/local/bin/postfwd-health

USER postfwd
# No DNS (every rule is local), policy socket in the mail IPC dir, and the
# rate counters saved on shutdown and loaded at start (--save_rates) and
# kept across a SIGHUP rule reload (--keep_rates).
ENTRYPOINT ["postfwd3", "--nodaemon", "--stdout", "--nodns", \
    "--user", "postfwd", "--group", "postfwd", \
    "--proto", "unix", "--port", "/run/rootless-ipc/mail/postfwd.sock", "--server_umask", "0111", \
    "--save_rates", "/var/lib/postfwd/rates", "--keep_rates", \
    "--file", "/etc/postfwd/postfwd.cf"]
