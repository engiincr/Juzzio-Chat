# 🛡️ Security Policy

## Supported versions

Only the **latest release** on [GitHub Releases](https://github.com/engiincr/Juzzio-Chat/releases/latest) receives security fixes. The app notifies you in-app as soon as a new version is published.

## Reporting a vulnerability

Please report vulnerabilities **privately** to **engiincr@pm.me** — do not open a public issue.

Include, if possible:

- affected version and component (app, database function, edge function),
- steps to reproduce or a proof of concept,
- the impact you observed.

You will receive a reply within 7 days. Good-faith reports that do not cause harm are never subject to legal action. Fixed issues are announced in the **🔒 Security & privacy** section of the release notes.

## What we already do

- End-to-end encryption for 1:1 chats (X25519 + ML-KEM-768 hybrid, AES-256-GCM), fail-closed.
- Row-level security on every table; privileged actions only through audited server functions.
- No secrets in the repository: automatic secret scanning (current tree and full Git history) and a strict `.gitignore` on every push.
- Signed releases; an APK with a different signature cannot be installed over the app.
