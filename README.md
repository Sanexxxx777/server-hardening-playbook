# Server Hardening Playbook

A practical, battle-tested checklist for locking down a production Linux server — written after learning some of these lessons the hard way.

Most "hardening guides" are either a wall of `sysctl` flags nobody applies, or a vendor benchmark you skim once and forget. This one is different: every item here maps to a **real way servers get owned** — an exposed port, a weak remote-desktop password, a secret in git, a database with no auth — and gives you the exact command to close it, plus how to *verify* it actually closed.

If you run a VPS, a side-project box, or a small fleet and you don't have a security team, this is for you.

> **The one lesson that matters most:** a service is only as safe as the interface it listens on. A strong password on a service exposed to `0.0.0.0` is a weak setup. No password on a service bound to `127.0.0.1` behind a default-deny firewall is a strong one. Reachability beats secrecy. Start there.

---

## The 10-minute triage

If you do nothing else, do these five. They close the most common real-world entry points.

```bash
# 1. Is anything listening on all interfaces that shouldn't be?
ss -tlnp | grep -vE '127.0.0.1|::1'

# 2. Is SSH password login disabled? (should print: no)
sshd -T | grep -i '^passwordauthentication'

# 3. Is the firewall default-deny? (should show DROP/deny policy)
sudo iptables -S INPUT | head -1        # -P INPUT DROP  ==  good

# 4. Any database answering with no auth?
redis-cli ping 2>/dev/null              # PONG with no password  ==  bad
mysql -u root -h 127.0.0.1 -e 'SELECT 1' 2>&1 | grep -q denied && echo "mysql: TCP root blocked (good)"

# 5. Any secrets committed to git?
git log -p | grep -iE 'api[_-]?key|secret|password|private[_-]?key|token' | head
```

Anything that comes back "wrong" above has a dedicated section below.

---

## Contents

| # | Topic | The failure it prevents |
|---|-------|-------------------------|
| 1 | [SSH](docs/01-ssh.md) | Password brute-force → shell |
| 2 | [Firewall](docs/02-firewall.md) | Forgotten service exposed to the internet |
| 3 | [Service binding](docs/03-service-binding.md) | App on `0.0.0.0` reachable by anyone |
| 4 | [Remote desktop (VNC/RDP)](docs/04-remote-desktop.md) | Weak-password screen-share → full desktop |
| 5 | [Secrets](docs/05-secrets.md) | Key in git / hardcoded → stolen credential |
| 6 | [Database auth](docs/06-database-auth.md) | Auth-less redis / empty DB password |
| 7 | [Passwords](docs/07-passwords.md) | Guessable / short credentials |
| 8 | [Attack-surface audit](docs/08-attack-surface-audit.md) | Drift — a new hole opens and nobody notices |
| 9 | [Incident response basics](docs/09-incident-response.md) | Making a breach worse while reacting to it |
| 10 | [Change discipline](docs/10-change-discipline.md) | Breaking prod while trying to secure it |

There's a condensed one-page version in [CHECKLIST.md](CHECKLIST.md).

---

## Philosophy

**Reachability first, then auth, then everything else.** The order is deliberate. A misconfigured firewall or a service on the wrong interface is worth more to an attacker than a weak password, because it turns a local problem into a remote one. Fix what's reachable before you polish what's secret.

**Every control needs a verification.** "I disabled password login" is a belief. `sshd -T | grep passwordauthentication` returning `no` is a fact. This playbook pairs every change with the command that proves it took effect — because the gap between "I edited the config" and "the running service actually changed" is where most hardening quietly fails. (Reloading isn't restarting; a config on disk isn't a config in memory.)

**Defense in depth, not defense in one place.** A database should be bound to localhost *and* behind a firewall *and* password-protected. Any single layer can fail — a firewall gets flushed, a bind address gets reverted in a deploy — and the others still hold.

**Least surface.** The most secure service is the one that isn't running. Before you harden something, ask whether it needs to be exposed — or exist — at all.

---

## Who this is for

Solo developers, indie hackers, small teams, and anyone running their own boxes without a dedicated security function. It assumes a Debian/Ubuntu-family server and root (or sudo) access. The concepts transfer to any Linux; the exact commands are written for the common case.

It is **not** a compliance framework, a pentest methodology, or a substitute for a real security review of a high-value target. It's the practical 80% that stops the opportunistic 99% of attacks.

---

## Contributing

Found a sharper command, a missing failure mode, or a distro-specific gotcha? PRs and issues welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Keep the format: **failure → fix → verify.**

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.

---

Maintained by **Aleksandr Shulgin ([@Aleksandr_NFA](https://t.me/Aleksandr_NFA))** · GitHub [@Sanexxxx777](https://github.com/Sanexxxx777)
