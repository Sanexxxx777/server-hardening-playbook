# 7. Passwords

When a password *is* the wall (a database, a panel, a disk key), it should be one nobody brute-forces this century. The rules are simple and mostly about not being clever.

## Failure

- Short, human-chosen, or reused passwords.
- Passwords invented by hand ("Tr0ub4dor&3") — low entropy, and you think they're strong.
- The same password across services, so one leak unlocks several.

## Fix

**Generate, don't invent. Long, random, from a real source of entropy.**

```bash
# 32+ characters of real randomness
openssl rand -base64 32

# or
pwgen -sy 32 1

# or, letters+digits only (safe anywhere)
openssl rand -base64 48 | tr -d '/+=' | cut -c1-40
```

- **Length beats symbol soup.** A 40-character base64 string is ~240 bits of entropy — unbrute-forceable by any physical machine, ever. Sprinkling `!@#$` adds little entropy and often *breaks* things (see below). Reach for length first.
- **One secret, one place.** Never reuse. A password manager (or an encrypted secrets file) makes this painless.
- **Store, don't memorize.** These aren't passwords you type; they're credentials a service reads. Put them in a `600` file or a manager — see [docs/05-secrets.md](05-secrets.md).

## Watch for symbols that break parsing

Special characters are fine in a vault but dangerous in passwords that flow through shells and config files:

- `space`, `"`, `'`, `` ` ``, `$`, `#`, `\` routinely break shell quoting, `.env` parsing, and config files.
- If a value goes into a `redis.conf`, a connection string, or a shell variable, keep it to `[A-Za-z0-9]` plus safe symbols like `_ - . + /`.

The entropy you'd gain from exotic symbols is negligible next to just adding characters. Long + boring > short + spicy.

## Know your protocol limits

Some legacy schemes cap password length and will **silently truncate** — meaning your long password isn't the length you think:

- **Classic VNC (VncAuth)**: max **8 characters** (DES 8-byte key). Anything longer is discarded. Don't rely on the password; rely on loopback + SSH tunnel (see [docs/04-remote-desktop.md](04-remote-desktop.md)).
- Check any old protocol's real limit *before* generating, so you don't get a false sense of strength.

When a protocol caps you short, compensate at a different layer — restrict reachability instead of trusting the secret.

## Verify

```bash
# The password you generated is actually the length you expect:
echo -n "$PW" | wc -c

# For a service that stores it, confirm the wrong password is refused
# and the right one works (example: redis)
redis-cli ping 2>&1 | grep -qiE 'NOAUTH' && echo "refuses no-password: good"
```

## The standing rule

Every credential you generate for real use: **maximum strength by default, generated not guessed, mindful of protocol limits.** It costs one command. There's no reason to ever ship a weak one.
