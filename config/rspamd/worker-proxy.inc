# rspamd local.d/worker-proxy.inc — milter proxy for Postfix
# Postfix reaches this socket through the dedicated rspamd-milter IPC dir.

bind_socket = "/run/rootless-ipc/rspamd-milter/milter.sock mode=0666";
upstream "local" {
  default = yes;
  self_scan = yes;
}
