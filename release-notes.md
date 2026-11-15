# Juzzio v1.2.9 — Glass Menu, GIFs, Message Requests & Sturdier Calls

## 🎯 Why did this update come?

On some phones names starting with an emoji crashed the app; some actions showed an unreadable "P0001" error; message reactions spilled outside the bubble; the birthday celebration closed with the back button; a yellow line appeared while sending; strangers could send unlimited messages. A copyright audit was also done, file security was hardened and calls are sturdier on weak internet.

## ✨ What's new?

- ✨ New glass context menu: 7 quick reactions + every emoji; Reply, Copy, Translate, Copy link, Forward, Forward without name, Save to cloud, Report, Select and Select from author
- ☑️ Multi-select: select several messages, copy, forward or delete them (back closes the selection)
- 🎞️ 42 funny, wordless animated GIFs (sleepy, laughing, dancing, shy…) — drawn by Juzzio itself; searchable in your language. New "GIF" tab in the emoji panel
- ✉️ Message requests: someone who is not your friend can send at most 3 messages until you reply ("2 messages left"); you get a Request box and a Spam box; accepting notifies them "accepted your pending message". Private accounts require a friend request first
- ⚠️ A clear risk warning before downloading a file from someone you don't know
- 🔎 Search by username and view a profile without adding the person
- 🎵 Share music in chats: cover, play/stop, ⋮ menu (Set as profile music, Listen to the full song on Apple Music, Report). Music stops automatically on a call, when the app goes to the background or when other audio plays
- 📞 In calls both sides see who lost connection ("… waiting"), a soft tone plays while reconnecting; video quality adapts to the network 720p → 480p → 360p; if the main server is unreachable a backup server is used
- 🔐 Locked chats open with the new green verification screen (step indicator, code boxes, "Verified")
- 👉 Swipe right in the chat list → pin; 5-second "Undo" after deleting
- 🌙 The real moon phase of today next to Juzzio under "Your space"; a more realistic weather theme (shaded clouds, cratered moon, glowing sun)
- 🎨 The default theme is now Midnight Blue
- 🎬 Smooth page transitions between the welcome, sign-in and sign-up pages
- 📎 The attach menu has a new Liquid Glass look; paperclip and a white mic in the composer
- 🎥 A one-time "What's new?" video for people updating from 1.2.8
- 🩺 System Health: translation, captions (Deepgram), the call server and the backup server are checked automatically and repaired when possible

## 🛠️ What was fixed?

- Fixed the "string is not well-formed UTF-16" crash for names starting with an emoji
- Clear error messages in every language instead of codes like "P0001"
- Message reactions now sit INSIDE the bubble next to the time; the reaction animation plays at the bubble corner (the feature is kept)
- The birthday celebration no longer stops when you press back; it only stops when you leave the chat
- The yellow line while sending is gone; text messages now arrive with the same springy animation as emojis
- An incoming call pauses the open story and its music; profile music stops immediately
- The weather theme no longer draws over stories, videos or the chat window
- Juzzio Community images are sent at full size; even if an image fails to load its space stays visible, with no jumping
- You no longer appear "online" while the app is in the background
- Replying from a notification no longer removes the sender's photo
- Fixed the admin header and "Welcome" overflow; long names are shortened neatly everywhere
- Stories are permanently deleted together with their media files after 24 hours

## 🔒 Security & privacy

- File security: executable/script files like .php, .jsp, .exe, .apk, .html, .svg, .js, hidden double extensions and files whose content doesn't match their extension are blocked on the device both when sending and opening; the server also accepts only allowed types
- Old overly broad storage rules were removed (one user could delete or overwrite another user's files)
- Phishing link warning: shortened, IP-address, look-alike or executable-download links are flagged before opening
- Script patterns in comments, bios and captions are stripped on the server (XSS)
- Admin security: single founder admin lock, tamper-evident (hash-chained) audit log and an automatic brake on mass destructive actions
- Copyright audit: all music and videos are Juzzio's own; third-party attributions and open-source licenses are on the Legal page
- Error reports are notified only to the founding administrator

## ⬇️ Download

- Latest: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- This version: `juzzio-v1.2.9-release.apk` (120.67 MB)

## ✅ Verify the APK

```bash
sha256sum Juzzio-latest.apk
# 97f9a69317bfbf0b9d9cab4d49069e993a21734f6438b04081f14ca5909ba468  Juzzio-latest.apk
```

Built: 2026-11-15 15:21 UTC — GitHub Actions
