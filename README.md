# rootless-stack / mail

**Needs:** [base](https://github.com/rootless-stack/base), [ldap](https://github.com/rootless-stack/ldap), [dns](https://github.com/rootless-stack/dns) (or another DNSSEC-validating resolver), running.

A complete mail server: Postfix (SMTP), Dovecot (IMAP, LMTP, Sieve), Rspamd
(spam filtering, DKIM, DMARC checks), ClamAV, and DANE/MTA-STS for outbound
TLS.  Users, aliases and domains come from the [ldap](https://github.com/rootless-stack/ldap) stack.

| Container | Runs as | Network |
| --- | --- | --- |
| `mail-postfix` | root (= `mail-svc`), workers as postfix | host |
| `mail-dovecot` | root (= `mail-svc`), workers as dovecot / vmail | host |
| `mail-tlspol` | `mail-svc` (keep-id) | host |
| `mail-rspamd` | `mail-svc` (keep-id) | `mail` |
| `mail-redis` | `mail-svc` (keep-id) | `mail` |
| `mail-clamd` | `mail-svc` (keep-id) | `mail` |
| `mail-postfwd` | `mail-svc` (keep-id) | none |

Postfix, Dovecot and tlspol use the host network: smtpd and IMAP see real
client addresses (logs, brute-force blocking, `mynetworks =
127.0.0.1/32`), and tlspol reaches the host's validating resolver.  They
still run as the unprivileged `mail-svc` user.  Everything between the
containers is a Unix socket under `/run/rootless-ipc/`.

Ports: 25 (SMTP), 465 and 587 (submission), 993 (IMAPS), 4190
(ManageSieve).  Rootless processes may bind them only with
`net.ipv4.ip_unprivileged_port_start = 25` (see Setup).

## Requirements

- A certificate for `mail_hostname`, from an ACME client of your choice.
- A **DNSSEC-validating resolver** on the host: [dns](https://github.com/rootless-stack/dns),
  or your own in `dns_resolvers`.  Without one, Postfix's DANE checks
  silently fall back to opportunistic TLS.
- Python 3.11+ with Jinja2 for rendering the config (`python3-jinja2`).
- DNS: MX, SPF, DKIM (below) and DMARC records for each domain.

## Setup

**In lldap** (web UI):

1. A read-only user (e.g. `readonly`) in the group `lldap_strict_readonly`.
2. A group `domain-<domain>` for every domain in `mail_domains`.
3. Mail users: each needs an email address (`mail`).  Optional user
   attributes, created as custom attributes in the UI: `mailAlias` (list
   of further addresses) and `mailQuotaBytes` (default 1 GiB).

**As root:**

```sh
git clone https://github.com/rootless-stack/mail /opt/rootless-stack/mail
useradd --create-home --home-dir /srv/mail-svc --shell /usr/sbin/nologin mail-svc
grep mail-svc /etc/subuid /etc/subgid       # both must list a range
loginctl enable-linger mail-svc
echo 'net.ipv4.ip_unprivileged_port_start = 25' > /etc/sysctl.d/50-rootless-stack.conf
sysctl --system
sudo -u mail-svc -H -s
```

The sysctl lets every user bind ports 25-1023.  To reserve the mail
ports to `mail-svc` and the rest to system services, add the optional
[port reservation](https://github.com/rootless-stack/base#optional-port-reservation)
with the line `mail-svc tcp:25 tcp:465 tcp:587 tcp:993`.

**As `mail-svc`:**

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
cd ~ && umask 077
R=/opt/rootless-stack
mkdir -p secrets/dkim certs data/{vmail,queue,rspamd,redis,clamav,fangfrisch,postfwd} \
  .config/containers/systemd .config/systemd/user
cp $R/mail/vars.example.toml vars.toml       # then edit it

printf %s "$(openssl rand -hex 32)" > secrets/redis_password
printf %s 'the readonly user password' > secrets/ldap_readonly_password
chmod 0444 secrets/redis_password

# One DKIM key per domain; publish the printed record as
# <selector>._domainkey.<domain> TXT.
for d in example.org; do
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out secrets/dkim/$d.mail.key
  printf '%s TXT "v=DKIM1; k=rsa; p=%s"\n' "mail._domainkey.$d" \
    "$(openssl pkey -in secrets/dkim/$d.mail.key -pubout -outform DER | base64 -w0)"
done

# Your ACME client delivers fullchain.pem and privkey.pem into ~/certs.

python3 $R/base/render.py $R/mail/config config vars.toml secrets
python3 $R/base/render.py $R/mail/tmpfiles.d tmpfiles vars.toml secrets
podman unshare chown 5000:5000 data/vmail

cp $R/mail/quadlet/* .config/containers/systemd/
cp $R/mail/systemd/* .config/systemd/user/

# Pull only signed images (base: "Signed images and automatic updates").
mkdir -p .config/containers/registries.d
cp $R/base/containers/policy.json .config/containers/
cp $R/base/containers/registries.d/* .config/containers/registries.d/
```

**As root** again, for the socket directories:

```sh
install -m 0644 /srv/mail-svc/tmpfiles/rootless-ipc-mail.conf /etc/tmpfiles.d/
systemd-tmpfiles --create
```

**As `mail-svc`**, start it:

```sh
systemctl --user daemon-reload
systemctl --user enable --now mail.service mail-certs.path
systemctl --user status 'mail*'
```

Optionally, keep the images current:
`systemctl --user enable --now podman-auto-update.timer`.

ClamAV downloads its signatures on the first start, which takes a few
minutes; postfix waits for it.

## Certificates

`~/certs/fullchain.pem` and `~/certs/privkey.pem`, owned by `mail-svc`.
When `fullchain.pem` changes, `mail-certs.path` reloads Postfix and Dovecot.
Copy `privkey.pem` first, then `fullchain.pem`.

With DANE (TLSA records for your MX), a renewal that changes the key must
publish the new TLSA record and wait two TTLs before the new certificate
reaches `~/certs`, or remote servers defer mail to you meanwhile.

## Optional ClamAV feeds

SecuriteInfo and MalwarePatrol feeds load when their credentials exist.  Put
them in `~/secrets/securiteinfo_customer_id` and
`~/secrets/malwarepatrol_receipt`, then add a drop-in
`~/.config/containers/systemd/mail-clamd.container.d/feeds.conf`:

```ini
[Container]
Volume=%h/secrets/securiteinfo_customer_id:/run/secrets/securiteinfo_customer_id:ro,Z
Volume=%h/secrets/malwarepatrol_receipt:/run/secrets/malwarepatrol_receipt:ro,Z
```

## Behaviour worth knowing

- **Submission only on 465/587.**  Port 25 never offers AUTH.  A logged-in
  user may send as their `mail` address and every `mailAlias`.
- **Fail closed.**  While Rspamd is down, mail is deferred (4xx), never
  delivered unscanned or sent unsigned.
- **Daily outbound cap.**  postfwd defers outgoing mail beyond 1000
  recipients a day (`config/postfwd/postfwd.cf`).
- **Spam training.**  Moving a message into Junk trains it as spam, moving
  it out trains ham; incoming spam is filed into Junk.
- **Quota.**  1 GiB per mailbox unless `mailQuotaBytes` says otherwise;
  postmaster@`primary_domain` gets a warning at 90 %.
- **Not included yet:** sending DMARC aggregate reports, fetching remote
  mailboxes.

## Updating

Pull the repository, then render and copy again, as in Setup, and run:

```sh
systemctl --user daemon-reload
systemctl --user restart mail.service
```
