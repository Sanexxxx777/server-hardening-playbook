# 8. Attack-surface audit

Hardening is not a one-time event. Servers drift: a deploy reverts a bind address, someone installs a tool "for a minute", a config gets copied from a less careful box. The job is to *notice* when a new hole opens.

## Failure

You hardened the server in January. In March, a new service quietly started listening on `0.0.0.0`, or a firewall rule got flushed during an unrelated change. Nobody looked. The hole stays open until someone finds it — and it usually isn't you who finds it first.

## Fix

**Audit the listening surface regularly, and alert on *change* from a known-good baseline.**

### The one command to run often

```bash
# Everything reachable from the network — review each line:
ss -tlnp | grep -vE '127.0.0.1|::1'
```

For every entry, you should be able to say *why* it's public. If you can't, that's your finding.

### Baseline + drift detection

Snapshot the known-good state, then compare against it on a schedule:

```bash
# Capture a baseline of externally-listening ports:
ss -tln | awk '{print $4}' | grep -vE '127.0.0.1|::1' | sort -u > /root/.surface-baseline

# Later (cron), diff current against baseline and alert on any difference:
ss -tln | awk '{print $4}' | grep -vE '127.0.0.1|::1' | sort -u > /tmp/surface-now
diff /root/.surface-baseline /tmp/surface-now || echo "SURFACE CHANGED — investigate"
```

Wire the diff into a cron job that pings you (email, a bot, a webhook) when it's non-empty. A sentinel like this turns "a port opened three weeks ago" into "a port opened, and I knew within the hour."

> **Update the baseline only on purpose.** When *you* make a legitimate change, re-snapshot the baseline. An alert you can't explain means the box is being changed by someone else — investigate it, don't silence it by re-baselining.

### What else to watch

- **New listeners** (the command above).
- **Firewall rule count** — a sudden drop can mean rules were flushed.
- **SSH config drift** — `sshd -T | grep passwordauthentication` should stay `no`.
- **New authorized_keys** — an added key you didn't add is a red flag.
- **Unexpected cron jobs** and outbound connections.

## Verify

The audit *is* the verification. The point is that it runs on a schedule without you remembering to — set the cron, confirm you receive an alert when something changes (test it by opening a port deliberately, then closing it).

## Supply-chain surface

Your attack surface includes what you *install*. Before adding a new package, extension, or third-party script, treat it as untrusted code: check what it pulls in, prefer pinned versions, and scan dependencies. A read-only dependency scanner run after each install keeps this honest.
