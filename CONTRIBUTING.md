# Contributing

Thanks for wanting to make this sharper. This playbook stays useful by being **practical, verifiable, and honest** — contributions should keep it that way.

## What makes a good addition

Every item follows the same shape:

1. **Failure** — the concrete way this bites you. Not "it's best practice", but "here's what an attacker does / here's what breaks."
2. **Fix** — the exact command(s). Copy-pasteable, for the Debian/Ubuntu common case.
3. **Verify** — the command that *proves* the fix took effect. This is non-negotiable; a fix without a verification is a belief.

If you can't write the "verify" step, the item probably isn't ready.

## Good contributions

- A missing failure mode with a real fix and verification.
- A sharper or more portable command than what's there.
- A distro-specific gotcha (with the distro named).
- Corrections — if something here is wrong or outdated, say so with evidence.

## Please don't

- Add walls of untested `sysctl`/kernel flags without explaining the threat each one addresses.
- Turn this into a compliance checklist or a pentest guide — it's a practical hardening playbook.
- Include anything offensive (exploit code, attack tooling). This is defensive material only.

## How

Open an issue to discuss anything substantial, or send a PR for focused changes. Keep edits surgical and the tone plain. Match the existing **failure → fix → verify** format.

## License

By contributing you agree your work is licensed under the project's [MIT License](LICENSE).
