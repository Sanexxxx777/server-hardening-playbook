# 5. Secrets

A leaked credential is worse than a leaked service — a service you can firewall off, but a stolen key works from anywhere until you rotate it. And most secret leaks are self-inflicted: committed to git, hardcoded in source, or left world-readable.

## Failure

- An API key, private key, HMAC secret, or database password is **hardcoded in source** and committed to git.
- Secrets sit in a config file that's tracked in the repo.
- A `.env` file is world-readable (`chmod 644`), so any local user or compromised process can read it.

Git history is forever. Once a secret lands in a commit and gets pushed, deleting it in a later commit does *nothing* — it's still in the history, on every clone, and likely already scraped by a bot. The only remedy is rotation.

## Fix

**Keep secrets out of code, out of git, and readable only by their owner.**

```bash
# Secrets live in a .env file, locked down:
chmod 600 .env          # owner read/write only
chown appuser:appuser .env

# .env is NEVER tracked:
echo '.env' >> .gitignore
echo '*.key' >> .gitignore
echo '.env.*' >> .gitignore
```

Load them at runtime from the environment, never inline in the code:

```python
import os
API_KEY = os.environ["API_KEY"]          # not API_KEY = "sk-live-..."
```

Commit a `.env.example` with the *keys* and dummy values so collaborators know what's needed, without the real secrets.

## Scan before every push

Make leak-detection a habit, not an afterthought. A pre-push grep catches the obvious cases:

```bash
git diff --cached | grep -iE 'api[_-]?key|secret|password|private[_-]?key|-----BEGIN|token[[:space:]]*=' && \
  echo "!! possible secret staged — review before commit" && exit 1
```

For real coverage, use a dedicated scanner:

```bash
# gitleaks — scans working tree AND history
gitleaks detect --source . --verbose
```

Wire it into a pre-commit hook or CI so it runs automatically.

## If a secret already leaked

1. **Rotate it immediately** — generate a new one and revoke the old. Assume the leaked value is already compromised.
2. Only *then* worry about scrubbing history (`git filter-repo`, or just accept it and move on if the secret is dead).
3. Rotation is the fix. Deleting the commit is cosmetic.

## Verify

```bash
# Permissions locked down?
ls -l .env                       # should be -rw------- (600)

# Nothing sensitive tracked?
git ls-files | grep -iE '\.env$|\.key$|secret|credentials'   # should be empty

# History clean?
git log -p | grep -iE '-----BEGIN|api[_-]?key|password' | head
```

## Reporting secrets in findings

When you *report* a leak (in a ticket, a log, a review), reference it by **location and type only** — `config.py:42, API key` — never paste the value. A finding that quotes the secret just leaks it a second time.
