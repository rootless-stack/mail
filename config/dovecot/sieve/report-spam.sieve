require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

# Triggered when a message is moved/copied INTO the Junk mailbox.
# Pipe the full message to rspamd's learnspam endpoint.
# :copy keeps the message in the mailbox (don't consume it).
pipe :copy "learn-spam.sh";
