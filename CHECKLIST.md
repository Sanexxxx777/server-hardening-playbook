# Hardening Checklist

One page. Print it, run it on a new box, run it again quarterly on old ones. Each line links to the section with the how-and-why.

## Access
- [ ] SSH password authentication **disabled** — `sshd -T | grep passwordauthentication` → `no` · [§1](docs/01-ssh.md)
- [ ] Root login key-only or disabled — `PermitRootLogin prohibit-password` / `no` · [§1](docs/01-ssh.md)
- [ ] Login works by **key** before passwords were turned off · [§1](docs/01-ssh.md)
- [ ] `fail2ban` installed and watching sshd · [§1](docs/01-ssh.md)
- [ ] No shared root private keys between hosts (forced-command users instead) · [§1](docs/01-ssh.md)

## Network
- [ ] Firewall policy is **default-deny** inbound — `iptables -S INPUT | head -1` → `DROP` · [§2](docs/02-firewall.md)
- [ ] Only intended ports open; each one justified · [§2](docs/02-firewall.md)
- [ ] Rules **persist** across reboot (`netfilter-persistent` / `ufw enable`) · [§2](docs/02-firewall.md)
- [ ] IPv6 firewall mirrors IPv4 (`ip6tables`) · [§2](docs/02-firewall.md)
- [ ] Cross-server ports restricted **by source IP**, not open to the world · [§2](docs/02-firewall.md)

## Services
- [ ] Nothing on `0.0.0.0` that only needs localhost — `ss -tlnp | grep -vE '127.0.0.1|::1'` · [§3](docs/03-service-binding.md)
- [ ] Public services sit behind a reverse proxy / tunnel; apps bound to `127.0.0.1` · [§3](docs/03-service-binding.md)
- [ ] Remote desktop (VNC/RDP) **loopback-only + SSH tunnel**, never exposed · [§4](docs/04-remote-desktop.md)
- [ ] Unused services stopped (least surface) · [§6](docs/06-database-auth.md), [§8](docs/08-attack-surface-audit.md)

## Secrets & credentials
- [ ] No secrets in git — `git ls-files | grep -iE '\.env$|\.key$|secret'` empty · [§5](docs/05-secrets.md)
- [ ] `.env` files are `chmod 600` · [§5](docs/05-secrets.md)
- [ ] Secret scanner (gitleaks) run on the repo · [§5](docs/05-secrets.md)
- [ ] All passwords generated (32+ chars), not invented · [§7](docs/07-passwords.md)
- [ ] Protocol length limits accounted for (e.g. VNC = 8 chars) · [§7](docs/07-passwords.md)

## Databases
- [ ] redis requires a password — `redis-cli ping` → `NOAUTH` · [§6](docs/06-database-auth.md)
- [ ] DB root/admin verified over **TCP** (`-h 127.0.0.1`), not just socket · [§6](docs/06-database-auth.md)
- [ ] Databases bound to localhost · [§3](docs/03-service-binding.md), [§6](docs/06-database-auth.md)

## Ongoing
- [ ] Listening-surface baseline captured; drift alerts wired to cron · [§8](docs/08-attack-surface-audit.md)
- [ ] Every change: backup → surgical → verify → record · [§10](docs/10-change-discipline.md)
- [ ] Incident plan known before you need it (isolate, capture, rotate, rebuild) · [§9](docs/09-incident-response.md)

---

Run `scripts/audit-listeners.sh` for an automated pass over the reachability items.
