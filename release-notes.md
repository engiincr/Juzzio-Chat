# Juzzio v1.2.5 — Updates Verify Without Waiting

## 🎯 Why did this update come?

Tapping "Update" right after a release was announced could show "The update's verification data is not published yet". Two causes: the community announcement was sent before the APK was built, and GitHub served the signed version.json from a ~5 minute cache. Both are fixed at the root; the security rule (an unverified APK is never installed) is unchanged.

## ✨ What's new?

- ✅ Updates are verified instantly from the signed (ML-DSA-65) data in the release record — no waiting for GitHub's cache
- 🔁 If the data is not out yet, the app retries for up to 20 minutes and sends a "✅ Update ready" notification

## 🛠️ What was fixed?

- The Juzzio Community release announcement is now sent AFTER the APK and signed verification data are published
- The signed version.json is also attached to every release (a fixed, cache-free address)

## 🔒 Security & privacy

- An unverified or wrongly signed APK is still never downloaded or installed (fail-closed); the signature covers version name, build number and SHA-256 together
- Updates never install by themselves; they start on the user's tap

## ⬇️ Download

- Latest: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- This version: `juzzio-v1.2.4-release.apk` (112.18 MB)

## ✅ Verify the APK

```bash
sha256sum Juzzio-latest.apk
# c76f065349909384479e1b2f4d29e622b171c72d0a31710cf615d78ea0868264  Juzzio-latest.apk
```

Built: 2026-11-10 07:20 UTC — GitHub Actions
