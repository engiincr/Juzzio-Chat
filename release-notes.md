# Juzzio v2.1.0 — Juzzio 2.1: New Logo, Explore and Friend Requests

## 🎯 Why did this update come?

Juzzio 2.1: the new green ribbon J logo and a Neon Lime look that matches the design files. New sign-in/sign-up, Friend Requests page, people discovery (cards, matches, likes), My Profile QR and database hardening.

## ✨ What's new?

- 🟢 New official Juzzio logo: app icon, splash screen, notification icon and every screen
- 🎥 Video calls: up to 1080p · 60 fps, never below 480p · 60 fps; freezing when turning on or flipping the camera is fixed
- 🟢 New brand: green ribbon J logo (incl. app icon) and Neon Lime colours
- 🔐 New Sign up / Sign in screen: Remember me, Forgot password
- 👥 Friend Requests page: received/sent, mutual friends, Accept all, Withdraw
- 💜 Explore: meet new people — cards, like, super like, matches, who liked you (real users; hide anytime in Edit Profile)
- 🔳 My Profile QR: copy link, share, save to gallery, open a profile from a code or username
- 🔔 Requests, Mentions and System filters in notifications
- 🌐 "Live Translation · Active" badge in video calls
- 🖥️ Screen sharing in calls (Android and desktop): start/stop from the top bar
- 📷 Scan QR codes with the camera (Android/iOS), torch button and paste fallback
- 🌤️ Sky 2.1: weather ambience redesigned — sky colour by your local time, a sun that arcs through the day, the moon in its real phase, twinkling stars, clouds, windy rain, lightning, snow and fog
- ⚙️ New Settings: Account & Profile, Privacy & Security, two-step verification (authenticator app), scheduled quiet hours, translation mode (Real-time / Fast / High accuracy), storage ring chart, bubble corners, bold text, colour correction, FAQ, Download my data, Consents; Call Settings and sign-out dialog
- 📞 Call screens redesigned: new Calls tab, Voice Call, Video Call and full-screen Incoming Call (keypad removed — calls go over the internet)
- 🎧 Audio output picker: arrow next to Speaker for earpiece / speaker / wired / Bluetooth; plugging a headset switches to it, unplugging returns to the earpiece
- 🎬 Cinema Party room redesigned: theme-coloured cinema card, LIVE badge, glass control bar, seats for viewers
- 🛡️ Admin Panel: every section and module on the home page; each opens as its own full page
- 🔐 The two-step verification code now has a clear full page (6-box code, paste); Sign out and other dialogs are opaque and readable

## 🛠️ What was fixed?

- The selected bottom tab shows a lime underline
- Sign-in title and texts are centred

## 🔒 Security & privacy

- TRUNCATE/REFERENCES/TRIGGER removed from client roles on every table; signed-out (anon) writes fully blocked
- Explore never uses location or age; private accounts are never shown and anyone can hide from Explore

