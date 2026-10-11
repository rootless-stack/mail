# Log to stderr, not $LOGDIR/rspamd.log.  The rootfs is read-only
# (mail-rspamd.container `ReadOnly=true`) so the file logger fails —
# "cannot open desired log file … Read-only file system", crash-loop on
# 2026-09-21 — and a file inside the container overlay never reached
# journald anyway.  conmon ships stderr to the journal.
type = console;
# The console logger writes every level to stderr (journal priority err).
# notice keeps the per-message results (rspamd_task_write_log, which the
# rspamd dashboard counts) and drops the per-connection milter and
# controller chatter that made up nearly all of the ~60k lines a day.
level = "notice";
