#!/usr/bin/env bash
# audit-listeners.sh — read-only attack-surface audit.
# Reports what a server exposes; changes NOTHING. Safe to run anywhere, anytime.
#
# Usage:  sudo ./audit-listeners.sh
# Part of: github.com/Sanexxxx777/server-hardening-playbook

set -uo pipefail

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

bold "== Externally-reachable listeners (not on loopback) =="
ext=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep -vE '127\.0\.0\.1|\[::1\]' | sort -u)
if [ -z "$ext" ]; then
  ok "nothing listening off-loopback"
else
  echo "$ext" | while read -r a; do warn "reachable: $a  — does this need to be public?"; done
fi

bold "== SSH =="
pw=$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
[ "$pw" = "no" ] && ok "password auth disabled" || bad "password auth = '${pw:-unknown}' (want: no)"
rl=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')
case "$rl" in
  no|prohibit-password) ok "root login: $rl" ;;
  *) warn "root login: ${rl:-unknown} (prefer prohibit-password or no)" ;;
esac

bold "== Firewall =="
pol=$(iptables -S INPUT 2>/dev/null | awk '/^-P INPUT/{print $3}')
[ "$pol" = "DROP" ] && ok "INPUT policy: DROP (default-deny)" || bad "INPUT policy: ${pol:-unknown} (want: DROP)"

bold "== redis (if present) =="
if command -v redis-cli >/dev/null 2>&1; then
  if redis-cli ping 2>&1 | grep -qiE 'NOAUTH|Authentication'; then
    ok "redis requires auth"
  elif redis-cli ping 2>/dev/null | grep -q PONG; then
    bad "redis answered PONG with NO password"
  else
    ok "redis not reachable without auth (or not running)"
  fi
fi

bold "== MySQL/MariaDB over TCP (if present) =="
if command -v mysql >/dev/null 2>&1; then
  if mysql -u root -h 127.0.0.1 -e 'SELECT 1' >/dev/null 2>&1; then
    bad "root got in over TCP with no password"
  else
    ok "root refused over TCP (socket-only or password-protected)"
  fi
fi

bold "== Secrets in the current directory's git repo (if any) =="
if [ -d .git ]; then
  if git ls-files 2>/dev/null | grep -iqE '\.env$|\.key$|secret|credentials'; then
    bad "sensitive-looking files are tracked in git — review:"
    git ls-files | grep -iE '\.env$|\.key$|secret|credentials' | sed 's/^/      /'
  else
    ok "no obviously-sensitive files tracked"
  fi
fi

echo
bold "Done. This was read-only — nothing was changed."
