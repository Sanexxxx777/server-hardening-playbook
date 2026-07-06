# 9. Incident response basics

If a box is compromised, your instinct — reboot it, delete the bad stuff, patch and move on — often destroys the evidence you need and leaves the attacker's persistence intact. A little discipline in the first hour matters more than speed.

This is not a full IR framework. It's the handful of things that keep a bad day from getting worse.

## Don't make it worse

- **Don't reboot first.** A running compromised machine holds forensic state in memory and open connections. Rebooting can wipe that state *and* can leave disk in a half-cleaned condition where you can't tell what's trustworthy. Capture what you need before power-cycling.
- **Assume persistence.** Attackers add SSH keys, cron jobs, systemd units, and backdoored binaries. Deleting the one obvious process rarely removes them. Treat the whole host as untrusted.
- **Rotate every credential the host touched.** Any key, password, or token that lived on (or was typed into) the box is burned. Rotate all of them, including ones you "think" were safe.

## The reachability lesson, in reverse

Most small-server breaches trace back to something in this playbook that wasn't done: a remote-desktop or admin service exposed to `0.0.0.0` with a weak password, a database with no auth, a forgotten port with no firewall. When you do the post-mortem, you'll usually find the entry point was **reachable when it shouldn't have been.** That's why sections 1–3 come first.

## First-hour checklist

1. **Isolate** — tighten the firewall to your IP only, or pull the box off the network, so the attacker loses access while you work.
2. **Capture** — list processes, network connections, logged-in users, recent auth logs, cron, and `authorized_keys` before changing anything:
   ```bash
   ps auxf; ss -tnp; who; last -20
   crontab -l; cat ~/.ssh/authorized_keys; journalctl -u ssh --since '-2 days'
   ```
3. **Rotate** — every secret, key, and password associated with the host and its accounts (including provider/hosting logins).
4. **Rebuild, don't clean** — for anything valuable, the trustworthy path is a fresh OS install from known-good media, then restore data (not binaries) from backup. You can rarely prove a compromised host is *fully* clean.
5. **Re-harden before redeploying** — a freshly reinstalled box with no hardening is just the next victim. Apply sections 1–8 *before* it goes back into service.

## The takeaway

The best incident response is the incident you prevented. Everything in sections 1–8 exists so that section 9 stays theoretical. If you're reading this section because you need it right now: isolate, capture, rotate, rebuild — in that order — and don't reboot before you've captured.
