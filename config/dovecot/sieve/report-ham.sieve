require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment"];

# Triggered on IMAP COPY/MOVE out of INBOX.Junk — the source gate is the
# `imapsieve_from INBOX.Junk` block in 90-plugin.conf, because 2.4 leaves
# `vnd.dovecot.mailbox-from` empty.  imap.mailbox is the full virtual name.

# Skip ham learning if the destination is Trash (user just deleting spam,
# not actually saying the message was legitimate).
if anyof (
    environment :is "imap.mailbox" "INBOX.Trash",
    environment :is "imap.mailbox" "INBOX.Deleted Messages",
    environment :is "imap.mailbox" "INBOX.Deleted Items"
) {
    stop;
}

pipe :copy "learn-ham.sh";
