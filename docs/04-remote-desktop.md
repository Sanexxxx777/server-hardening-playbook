# 4. Remote desktop (VNC / RDP)

Graphical remote-access services are a favorite entry point precisely because people treat them casually — "it's just for me, I'll set a quick password." That quick password is the whole attack.

## Failure

A VNC or RDP server listens on `0.0.0.0` with a weak, guessable, or short password. Attackers scan for these ports constantly; a brute-forceable screen-share password is a direct path to a full interactive desktop session — and from there, to everything the logged-in user can do.

There's a nasty extra wrinkle with classic VNC: **the VncAuth protocol truncates passwords to 8 characters.** The RFB scheme uses a DES key derived from at most 8 bytes, so `vncpasswd` silently ignores anything past the eighth character. Your "32-character strong password" is really an 8-character one. You *cannot* make classic VNC auth strong by making the password longer.

## Fix

**Never expose remote desktop to the network. Bind it to localhost and reach it exclusively through an SSH tunnel.**

The security then comes from your SSH key (effectively unbrute-forceable), not from the 8-character VNC password — which becomes a minor second layer instead of the only wall.

Start the VNC server bound to loopback only:

```bash
# -localhost yes forces binding to 127.0.0.1
vncserver :2 -localhost yes -geometry 1280x800 -depth 24
```

Connect by first opening an SSH tunnel, then pointing your viewer at the local end:

```bash
# On your machine — forward a local port to the server's loopback VNC port
ssh -L 5902:localhost:5902 user@server        # keep this open

# Then connect your VNC viewer to:  localhost:5902
```

The VNC port is never open to the internet. Anyone scanning the server's public IP sees nothing.

When you're done, tear it down — don't leave a desktop session running:

```bash
vncserver -kill :2
```

## On a sensitive host, don't install it at all

If a machine handles anything valuable, the safest remote-desktop configuration is **no remote desktop**. Use SSH for everything and skip the GUI service entirely. Least surface beats best-configured surface.

## Verify

```bash
# VNC/RDP ports must appear ONLY on 127.0.0.1 — never 0.0.0.0:
ss -tlnp | grep -E ':590[0-9]|:3389'
```

If any remote-desktop port shows up on `0.0.0.0` or your public IP, it's exposed — fix the bind (`-localhost yes`) before doing anything else.

## Why this section exists

Weak, exposed remote-desktop auth is one of the most reliably exploited misconfigurations on small servers — precisely because it feels harmless. Treat it as: **loopback bind + SSH tunnel, always. No exceptions on production.**
