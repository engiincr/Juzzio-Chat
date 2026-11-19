# Juzzio v1.3.0 — Translated In-Call Messages, Speakerphone Fix & New Themes

## 🎯 Why did this update come?

On speakerphone your voice cut out when the other person spoke and translation stopped working; video could freeze during calls; offline phones sent false system errors to the admin panel; some headers were invisible in light mode; the double-tap reaction bounced below the message. Calls now also have translated in-call messaging, there are new themes, and admin panel security was tightened.

## ✨ What's new?

- 💬 Messages during voice and video calls: tap 💬 in the bottom bar; messages reach the other person translated into their language, with no translation between people who speak the same language
- 🔐 Change your locked-chats PIN or reset it to 0000 (key menu at the top right)
- 🎨 New themes: Forest Mint and Graphite Lime
- 🔔 Large unread counter in Notifications with one-tap "Mark all as read"
- 📞 Quick "Voice call" and "Video" cards on the Calls page
- ⛅ The icon next to Juzzio shows clouds when the weather is cloudy
- 👋 Time-of-day greeting on the Chats header

## 🛠️ What was fixed?

- Fixed your voice cutting out and translation failing on speakerphone when the other person spoke (captions now use the call's echo-cancelled microphone audio)
- On weak networks video calls lower the resolution instead of freezing
- System health no longer files false errors while offline or in the background
- Fixed white headers, back arrows and filters that were invisible in light mode
- Fixed the Notifications title being cut off as "Not..."
- Fixed the double-tap reaction bouncing below the message
- Removed the long "you speak the same language" notice in calls to save space
- Background cloud/moon/sun decorations are simpler and only appear at the top

## 🔒 Security & privacy

- Admin panel: sessions last 4 hours (remember: 7 days), at most 15 wrong passwords per 24 hours, at most 3 sessions at once; failed attempts are written to the audit log

## ⬇️ Download

- Latest: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- This version: `juzzio-v1.3.0-release.apk` (120.73 MB)

## ✅ Verify the APK

```bash
sha256sum Juzzio-latest.apk
# aa16161ccf9e724c151d31185a084786d7680cfa5a665a8800e5b3ba7574110e  Juzzio-latest.apk
```

Built: 2026-11-19 19:01 UTC — GitHub Actions
