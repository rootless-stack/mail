# Global delivery rules for every mailbox.  Rspamd marks spam with
# X-Spam: Yes; deliver it to the Junk mailbox before any personal rule or
# getmail folder routing can leave it in the inbox or another folder.
#
# fetchmail injects X-Deliver-To-Folder to preserve the remote mailbox
# (fetchmail, an optional add-on).  Strip that internal
# header even when the message is spam, then route non-spam fetched mail.
# The header is trusted only because nothing else can deliver it: Postfix's
# header_checks drop it at SMTP ingress, fetchmail drops the remote copy
# before it adds its own.
#
# `:create` ensures the destination folder exists — important because we
# might fetch from a remote folder Selina hasn't yet subscribed to locally
# (e.g. a custom Hotmail folder she added later).
# The visible mailbox name includes INBOX. (10-mail.conf); fileinto "Junk"
# would not address this namespace's Junk folder.

require ["fileinto", "mailbox", "variables", "editheader"];

set "folder" "";
if header :matches "X-Deliver-To-Folder" "*" {
    set "folder" "${1}";
    deleteheader "X-Deliver-To-Folder";
}

if header :is "X-Spam" "Yes" {
    fileinto :create "INBOX.Junk";
    stop;
}

if string :matches "${folder}" "?*" {
    fileinto :create "${folder}";
    stop;
}
