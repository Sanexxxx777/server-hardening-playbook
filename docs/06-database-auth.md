# 6. Database auth

Databases are the prize. An attacker who reaches an unauthenticated database gets your data directly — and often a foothold for more (redis, in particular, has several well-known paths from "no auth" to "remote code execution").

## Failure

- **redis with no `requirepass`** — anyone who can reach the port gets full read/write. Classic redis attacks can write files and pivot to RCE.
- **A database with an empty or default root password.**
- The database bound to `0.0.0.0` on top of either of the above.

These often hide behind "it's only on localhost" — which is true right up until a local RCE in some *other* service turns "localhost" into the attacker's position.

## Fix

**Bind to localhost, sit behind the firewall, AND require a password.** Three layers; any one can fail.

### redis

```bash
# Set a strong password (see docs/07-passwords.md for generating one)
redis-cli CONFIG SET requirepass "$(cat /path/to/generated/password)"
redis-cli -a "$THE_PASSWORD" CONFIG REWRITE     # persist to redis.conf

# And confirm it's bound to loopback in redis.conf:
#   bind 127.0.0.1
```

### MySQL / MariaDB

```sql
-- Give root a real password (or, better, use socket auth for local root)
ALTER USER 'root'@'localhost' IDENTIFIED BY 'STRONG_GENERATED_PASSWORD';
FLUSH PRIVILEGES;
```

Prefer application users with the *minimum* privileges they need — don't have apps connect as root.

### PostgreSQL

Local connections default to `peer`/`ident` auth (authenticated by OS user) in `pg_hba.conf`, which is safe for localhost. Make sure network connections require `scram-sha-256`, not `trust`.

## Verify — and don't fool yourself

Testing local DB auth has a trap: running `mysql -u root` as the system root user often succeeds via the unix socket or a `~/.my.cnf` — that is **not** proof the account has no password. Test the way an attacker would: **over TCP.**

```bash
# The real test — connect over the network stack, no socket shortcut:
mysql -u root -h 127.0.0.1 -e 'SELECT 1' 2>&1 | grep -q 'Access denied' \
  && echo "OK: TCP root is refused" \
  || echo "BAD: TCP root got in — empty/weak password"

# redis: no password should be refused
redis-cli ping 2>&1 | grep -qiE 'NOAUTH|Authentication' \
  && echo "OK: redis requires auth" \
  || echo "BAD: redis answered with no password"
```

> **The socket-vs-TCP distinction bit us once:** a quick `mysql -u root` succeeded and looked like an empty-password hole — but it was only the system root using socket auth. The TCP test showed the account was actually password-protected all along. Always verify over `-h 127.0.0.1` before declaring a database open *or* closed.

## Least surface

If a database isn't actually used (check: is the keyspace empty? has it served any real commands?), the best hardening is to **stop running it**. An unused service is pure attack surface with zero benefit.
