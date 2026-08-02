# 11. Integrity sentinel — noticing the breach at minute 10, not day 3

Everything in sections 1–10 reduces the odds of a breach. This section is about the remaining case: something *did* change on the box — a new SSH key, a new root user, a new public port, a foreign cron entry — and nobody is looking. In the incident that spawned this playbook, the attacker lived on the servers for days; every artifact they left (extra `authorized_keys` entry, new listener, cron persistence) was trivially observable the whole time. Nothing was watching.

**Failure mode:** post-exploitation persistence sits in plain sight (`authorized_keys`, uid-0 accounts, `sudoers`, public listeners, cron) and stays there, because "checking the server" is a manual habit that stops happening after week one.

## Fix: a 13 KB cron watchdog

[`scripts/sentinel/sentinel.sh`](../scripts/sentinel/sentinel.sh) snapshots the five things persistence actually touches and diffs them against a baseline you explicitly bless:

- `authorized_keys` of root and every user (sha256)
- uid-0 users from `/etc/passwd`
- `/etc/sudoers` + `sudoers.d` (sha256)
- public LISTEN ports (everything not bound to localhost)
- `/etc/crontab`, `/etc/cron.d`, user spools (sha256)

On deviation it sends one Telegram alert with a **human-readable summary** (which port opened, which file changed) and an inline button: *"that was me — bless the new state"*. Same-deviation alerts are deduplicated by diff hash; a daily heartbeat nags while a deviation stays unacknowledged. Separately, every **successful SSH login from a new IP** produces an alert that classifies the key fingerprint against a `known_keys` list — "our key, new IP (mobile pool)" versus "unknown key: alarm" — so the common false positive (you, from a new network) is labeled instead of ignored.

[`scripts/sentinel/sentinel-cron.sh`](../scripts/sentinel/sentinel-cron.sh) is the wrapper that alerts if the sentinel *itself* crashes — a watchdog nobody watches is theater.

Install sketch:

```bash
cp sentinel.sh sentinel-cron.sh /usr/local/bin/ && chmod +x /usr/local/bin/sentinel*.sh
install -m 600 /dev/null /root/.secrets/sentinel.env   # SENTINEL_TG_TOKEN=..., SENTINEL_CHAT_ID=...
cat > /etc/cron.d/sentinel <<'EOF'
*/10 * * * * root /usr/local/bin/sentinel-cron.sh check >/dev/null 2>&1
0 9 * * *    root /usr/local/bin/sentinel-cron.sh heartbeat >/dev/null 2>&1
EOF
sentinel.sh baseline    # bless the current state — do this ONLY on a state you trust
sentinel.sh test        # verify the Telegram channel end-to-end
```

Populate `/var/lib/sentinel/known_keys` with `SHA256:<fingerprint> human-name` lines (`ssh-keygen -lf ~/.ssh/id_ed25519.pub` gives you the fingerprint) so login alerts can tell your keys from foreign ones.

## Rules that keep it honest

- **`baseline` is a human decision.** Never automate re-baselining and never bless a deviation you can't explain — an unexplained alert means someone is on the box, and "make the alert go away" is exactly the wrong move.
- **Alert fatigue is the real enemy.** The script sends one message per distinct deviation, labels known keys on new IPs, and stays silent when clean. If you find yourself ignoring it, fix the noise, don't mute the channel.
- **The sentinel is a tripwire, not a defense.** It doesn't block anything. Its job is to shrink "attacker dwell time" from days to minutes; sections 1–8 are still what keeps them out.

Alert texts in the script are in Russian (it's a battle-tested production copy, published as-is) — translate the message strings to taste; the logic is language-agnostic.

## Verify

1. `sentinel.sh test` → message arrives in Telegram.
2. Open a throwaway port (`python3 -m http.server 8000 --bind 0.0.0.0`) → within 10 minutes you get an alert naming port 8000; close it, bless nothing — the alert clears on the next clean check.
3. `kill` the script mid-run or break its syntax → `sentinel-cron.sh` reports the crash once.
4. SSH in from a phone hotspot → login alert labels your key as known, new IP.
