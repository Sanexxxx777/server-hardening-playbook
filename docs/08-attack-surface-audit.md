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
- **New successful SSH logins** — alert on the first login from an IP you haven't seen before.
- **Unexpected cron jobs** and outbound connections.

### Make login alerts actionable — mark your own keys

A "new SSH login" alert is only useful if you can tell *your* login from an intruder's in one glance. If you log in from a mobile connection, your source IP changes constantly — alerting on every new IP trains you to ignore the alerts (alert fatigue), and a real intrusion hides in the noise.

The fix: don't key the alert on the IP, key it on the **key fingerprint**. Keep a small allowlist of the SSH key fingerprints you actually use, and have the alert label each login against it:

```bash
# Your legitimate key fingerprints, one per line: "SHA256:... human-readable name"
# stored at e.g. /var/lib/sentinel/known_keys

# When a login fires, pull its fingerprint from the auth log and look it up:
keyfp=$(grep -aoE 'SHA256:[A-Za-z0-9+/]+' <<<"$log_line")
name=$(awk -v fp="$keyfp" '$1==fp{$1="";sub(/^ +/,"");print;exit}' /var/lib/sentinel/known_keys)
```

Then the alert reads **"known key — laptop, just a new IP"** (benign) or **"key NOT in the allowlist / login by *password*"** (alarm — check `authorized_keys` now). A roaming IP stops being an alert; an unknown key stays one. Password logins should never appear once you've disabled them (Section 1) — if one does, that's the loudest signal on the list.

## Verify

The audit *is* the verification. The point is that it runs on a schedule without you remembering to — set the cron, confirm you receive an alert when something changes (test it by opening a port deliberately, then closing it).

## Supply-chain surface

Your attack surface includes what you *install*. Before adding a new package, extension, or third-party script, treat it as untrusted code: check what it pulls in, prefer pinned versions, and scan dependencies. A read-only dependency scanner run after each install keeps this honest.
