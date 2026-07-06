# 10. Change discipline

More production outages come from *fixing* things than from attacks. A hardening change that bricks SSH access or takes down a service is its own kind of incident. The habits here make every change reversible and verified.

## Failure

You edit a config to harden it, restart the service, and it doesn't come back — or worse, you're now locked out. No backup, no rollback, and the "quick security fix" became an outage. Or the change *looked* applied but the running service never picked it up, so you're now insecure *and* think you're safe.

## The four-step discipline

Apply this to every change — a config edit, a firewall rule, a service restart:

### 1. Back up first, know your rollback

Before touching anything, snapshot it and know the exact command to undo:

```bash
cp service.conf service.conf.bak_$(date +%Y%m%d_%H%M%S)
# rollback is now: cp service.conf.bak_... service.conf && restart
```

For anything critical, keep the rollback command written down *before* you make the change.

### 2. Change surgically

Touch only what the task requires. Don't "improve" the neighboring config while you're in there — every extra edit is extra risk and extra to debug if something breaks.

### 3. Verify by proof, not by faith

A change isn't done when you saved the file — it's done when you've *observed* the new behavior:

```bash
# config valid before reloading?
nginx -t          # sshd -t, redis-server --test, etc.

# service actually running the new config?
ss -tlnp | grep :PORT        # is it bound where you expect?
sshd -T | grep setting       # is the effective value what you set?
```

> **Reload is not restart.** Some changes (like a bind-address change in nginx) are picked up only by a full restart, not a reload. And a config on disk is not a config in memory until the service re-reads it. Verify the *running* state, not the file.

### 4. Record it

Note what changed and why — even a one-line commit or comment. Future-you debugging at 2am will thank present-you. If you changed a security control, the note is also your audit trail.

## Guardrails for dangerous commands

Some operations are irreversible or easy to fire at the wrong target. Put friction in front of them:

- **Prefer targeted over pattern-matched.** `kill 12345` (a specific PID you verified) is safe; `pkill -f name` and `kill $(pgrep ...)` can match the wrong process — including your own shell or an unrelated service. Kill by PID, or use the service manager (`systemctl`, `pm2`).
- **Confirm before the irreversible** — `rm -rf`, force-push, dropping a database, deleting a process. A second of "am I sure?" is cheaper than a restore.
- **On shared resources, never use the blunt instrument.** If several things share a backend, a "cancel/kill everything" command takes out more than you meant. Operate per-item.

## The payoff

Backup → surgical change → verify → record. It feels slower on the easy changes and saves you completely on the one change that would've taken down prod. Hardening is change; treat it with the same discipline you'd want for any production change.
