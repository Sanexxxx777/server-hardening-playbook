# 2. Firewall

The firewall decides what the internet can even *attempt* to reach. Get this right and a misconfigured service on the wrong port becomes a non-event instead of a breach.

## Failure

The firewall is a default-*allow* setup with a few blocks — or it's off entirely (`ufw` shows `inactive`, no iptables rules). Every port a service happens to open is now reachable from the whole internet. You install something for "just a quick test", it binds to `0.0.0.0`, and it's exposed the moment it starts.

## Fix

**Default-deny inbound. Allow only the ports you can name and justify.**

The right model is: block everything, then punch holes deliberately.

```bash
# Policy: drop everything inbound by default
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# Always allow loopback and established connections
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow only what you actually serve
sudo iptables -A INPUT -p tcp --dport 22  -j ACCEPT   # SSH
sudo iptables -A INPUT -p tcp --dport 80  -j ACCEPT   # HTTP
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT   # HTTPS
sudo iptables -A INPUT -p icmp -j ACCEPT              # ping (optional)
```

Persist the rules so they survive a reboot:

```bash
sudo apt install iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

`ufw` is a friendlier front-end for the same thing, if you prefer:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable
```

> **Pick one and know which is active.** `ufw` and raw `iptables` can disagree — `ufw status` may say `inactive` while `iptables` is doing the real work, or vice-versa. Check the layer that's actually enforcing (`iptables -S`) rather than trusting the front-end.

## Cross-server ports: restrict by source, not to the world

If a service genuinely needs to be reached by *another* server (a metrics relay, a backup target), don't open it to `0.0.0.0` — open it only to that server's IP:

```bash
sudo iptables -A INPUT -p tcp --dport 9000 -s 203.0.113.10 -j ACCEPT   # only from this host
```

This is the difference between "one trusted peer can connect" and "anyone on the internet can connect."

## Verify

```bash
# Policy is DROP:
sudo iptables -S INPUT | grep '^-P INPUT'          # -P INPUT DROP

# What's actually open to the world:
sudo iptables -S INPUT | grep -E 'dport|ACCEPT'
```

Then confirm from *outside* the box — scan your own IP from a different network and check that only intended ports answer. Don't assume; test.

> **Don't forget IPv6.** Rules for `iptables` do not cover `ip6tables`. A service listening on `::` can be wide open even when your IPv4 firewall is perfect. Mirror your policy with `ip6tables` (or let `ufw` handle both).
