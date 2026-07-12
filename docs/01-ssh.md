# 1. SSH

SSH is the front door. If it accepts passwords, it accepts brute-force. Automated bots hammer port 22 on every public IP continuously — the only winning move is to not have a password to guess.

## Failure

Password authentication is enabled. An attacker with a wordlist and time gets in — no exploit required, just patience against a weak or reused password.

## Fix

**Use keys, disable passwords entirely.**

```bash
# On your machine: create a key if you don't have one
ssh-keygen -t ed25519 -a 100        # ed25519 is modern, short, and fast

# Copy the public key to the server
ssh-copy-id user@server

# Confirm key login works BEFORE disabling passwords — or you'll lock yourself out
ssh user@server 'echo key-login-ok'
```

Then, on the server, edit `/etc/ssh/sshd_config` (or a drop-in in `/etc/ssh/sshd_config.d/`):

```
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password    # key-only for root, or 'no' to forbid root entirely
```

Reload and verify:

```bash
sudo systemctl reload ssh
sshd -T | grep -iE 'passwordauthentication|permitrootlogin|pubkeyauthentication'
```

> **Gotcha — drop-in ordering.** `sshd` reads config files in alphanumeric order and the *first* setting wins. A hardening file at `/etc/ssh/sshd_config.d/99-hardening.conf` can be silently overridden by an earlier `50-cloud-init.conf` that re-enables passwords. Always confirm the *effective* value with `sshd -T`, not just what you wrote in your file.
>
> **Gotcha — cloud-init regenerates the file on reboot.** Even if you edit or delete `50-cloud-init.conf`, cloud-init rewrites it on the next boot from its own config, quietly re-enabling passwords. To make the fix durable, also tell cloud-init to stop managing SSH password auth:
>
> ```bash
> # /etc/cloud/cloud.cfg.d/99-disable-ssh-pwauth.cfg
> ssh_pwauth: false
> ```
>
> This is a common trap on freshly-provisioned VPS images: the hardening looked applied, but a reboot silently undid it. Re-check `sshd -T | grep '^passwordauthentication'` *after* the first reboot, not just after applying.

## Verify

```bash
sshd -T | grep '^passwordauthentication'   # must be: no
```

Test from the outside — a password attempt should be refused outright:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no user@server
# expected: "Permission denied (publickey)."
```

## Then add fail2ban

Even with passwords off, `fail2ban` cuts log noise and blocks IPs probing for other weaknesses.

```bash
sudo apt install fail2ban
# defaults protect sshd out of the box; confirm it's watching:
sudo fail2ban-client status sshd
```

## Don't lock yourself out

- Keep an **open root session** in a second terminal while changing SSH config. If the new config breaks login, you can revert without a console/rescue trip.
- If your provider offers a web console (KVM/serial), know how to reach it *before* you need it.

## Notes on cross-server keys

If servers need to talk to each other (backups, sync), **do not** drop a root private key on one box that unlocks another — one compromised host then unlocks the rest. Use a dedicated, unprivileged user with a **forced command** that limits exactly what that key can run:

```
# in the target's authorized_keys, restrict the key to one command:
command="rsync --server --daemon .",no-pty,no-port-forwarding,no-agent-forwarding ssh-ed25519 AAAA...
```

A key that can only run one `rsync` is worth far less to an attacker than a key that opens a shell.
