# Juzzio v1.2.4 — Offline-first Juzzio, Smooth Chats & Replyable Notifications

## 🎯 Why did this update come?

Explore, chats, stories, calls, notifications, profile and tasks now open in their last-loaded state without internet; everything refreshes on its own when the connection returns and offline profile/settings changes are applied. The chat stutter when scrolling up is fixed at the root. Notifications are expandable with Reply and Mark as read. The admin legal bundle error (P0001) and the version field are fixed, the locked-chat PIN bypass is closed and the whole app switches language instantly.

## ✨ What's new?

- 📶 Offline-first: Explore opens in its last-loaded state; an "No internet connection" row where the cache ends; uncached images show a spinning loader and load by themselves when back online
- 📞 Calls page cached; toggling internet no longer empties it; pull-to-refresh added
- 🔔 Notifications, 👤 profile (posts, saved, counters, friends' profiles) and ✅ tasks/reminders are cached in the background and viewable offline
- 🎵 Profile music plays offline after the first listen; 📖 stories are pre-downloaded and watchable offline
- ✏️ Profile and settings changes made offline are kept and applied when you reconnect
- 💬 Expandable chat notifications: sender photo and name, group/channel name, stacked messages; Reply and Mark as read without opening the app
- 🖼 Received photos, videos and documents are saved to the gallery (Juzzio folder) and open offline (toggle in Settings → Chats; view-once never saved)
- ⚡ No waiting when sending photos, videos and documents: they appear instantly and upload in the background
- 😍 Tap a reaction badge to see who reacted with what (one reaction per person)
- 📤 Forward Explore posts and stories to 1:1 chats and groups; "Open post / Open story" button in chat
- 🧑‍💼 Admin panel greets you with your current photo; minimum version is picked from past packages with build number, ID, SHA-256, ML-DSA fingerprint and date
- 🎬 Glass "Portfolio · Creator Showreel" button on the creator page: a 26 s video starting with "Hello…" (plays offline)
- 🌍 Changing the app language instantly updates EVERY open screen, including sign-up/login policies, admin panel and dialogs
- ♀♂ Pink/blue gender icons at sign-up; password strength meter; +1 animation when adding a friend

## 🛠️ What was fixed?

- Chat stutter when scrolling up: swipe-to-reply no longer steals vertical scrolling; loading older messages no longer yanks you to the bottom
- Locked chats could be opened without the PIN: creating a PIN no longer unlocks; the lock closes again after 2 minutes and when leaving the chat
- Admin → Emergency → Legal bundle P0001: username is resolved on the server (case-insensitive) with clear errors for missing reason and expired session
- Minimum supported build couldn't take versions like 1.0.2: now picked from a package list
- People without a status no longer appear in the status strip
- Offline chats show the real last seen instead of "Last seen hidden"
- Every message type (view-once, contact card, location, video, image, poll, event, document) can be deleted from the long-press menu
- CI: failing test details are now visible on GitHub; admin log sentences and ambiguous imports are checked locally before push

## 🔒 Security & privacy

- Locked-chat unlock expires and re-locks on exit; the PIN is never stored
- Notification avatars are downloaded only from public https URLs with a 3 s limit; nothing is sent in hidden preview mode
- Only files from the app's own folders are saved to the gallery; encrypted media is decrypted on device and the temp file deleted; view-once media is never saved
- Legal bundle still requires the super-admin password session, a reason and is audit-logged
- End-to-end encryption, RLS and storage rules unchanged

## ⬇️ Download

- Latest: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- This version: `juzzio-v1.2.4-release.apk` (112.18 MB)

## ✅ Verify the APK

```bash
sha256sum Juzzio-latest.apk
# c76f065349909384479e1b2f4d29e622b171c72d0a31710cf615d78ea0868264  Juzzio-latest.apk
```

Built: 2026-11-10 07:20 UTC — GitHub Actions
