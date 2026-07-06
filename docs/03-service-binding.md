# 3. Service binding

This is the single highest-leverage habit in the whole playbook. Where a service *listens* matters more than almost anything else about it.

## Failure

A service binds to `0.0.0.0` (all interfaces) when it only ever needs to be reached locally — by a reverse proxy, a tunnel, or another process on the same box. Now it's exposed to every network the machine is on, and the only thing standing between it and the internet is the firewall. When (not if) the firewall gets flushed, misconfigured, or a cloud security-group changes, the service is instantly public. Databases, admin panels, dashboards, dev servers, metrics endpoints — this is how they leak.

## Fix

**Bind to `127.0.0.1` unless the service has a genuine reason to face the network. Put anything public behind a reverse proxy or tunnel.**

The public entry point (nginx, Caddy, a Cloudflare Tunnel, etc.) listens on `443`; it forwards to your app on `127.0.0.1`. The app itself is never directly reachable.

Common ways to set the bind address:

```bash
# Node/Express — pass the host to listen()
app.listen(PORT, '127.0.0.1')

# Python — bind explicitly
uvicorn.run(app, host='127.0.0.1', port=8000)
# aiohttp
web.TCPSite(runner, '127.0.0.1', PORT)

# nginx — bind the listen directive
listen 127.0.0.1:8080;

# redis — redis.conf
bind 127.0.0.1

# Docker — publish to localhost only, not all interfaces
docker run -p 127.0.0.1:8080:8080 ...     # NOT -p 8080:8080
```

Reverse proxies and tunnels connect over `127.0.0.1`, so **binding to localhost does not break public access** — the proxy still reaches the app; the open internet no longer can.

> **Gotcha — nginx `reload` won't rebind.** If you change a `listen` directive from `0.0.0.0:8080` to `127.0.0.1:8080`, `nginx -s reload` will *not* reopen the socket on the new address — it keeps the old listening socket for the same port. You need a full `systemctl restart nginx` to actually move the bind. Verify with `ss`, not with the config file.

## Verify

```bash
# Everything that is NOT on localhost is worth a second look:
ss -tlnp | grep -vE '127.0.0.1|::1'
```

Every line this prints is a service the network can reach. For each one, ask: *does this need to be public?* If a reverse proxy or tunnel fronts it, the answer is almost always no — bind it to `127.0.0.1` and let the proxy do its job.

## The mental model

Think of `0.0.0.0` as "publish to the world" and `127.0.0.1` as "available to this machine only." Most services you run are the second kind pretending to be the first because the default was lazy. Two layers — localhost bind **and** firewall — mean a single mistake in either one doesn't expose you.
