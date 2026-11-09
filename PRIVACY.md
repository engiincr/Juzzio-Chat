# 🔐 Juzzio Privacy Policy

Last updated: November 9, 2026 · App version: v1.0.0 (BETA · Early Access)

> 🇹🇷 The legally binding Turkish version (Privacy Policy and KVKK Disclosure Notice) is in [docs/legal/tr/PRIVACY.md](docs/legal/tr/PRIVACY.md). In the app, the Turkish text is shown when the app language is Turkish.

This document explains, **exactly as it is**, which personal data the Juzzio mobile app processes, why, who it is shared with, and what your rights are. The source code is public on GitHub, so every statement here can be verified against the code.

## 1. Data controller

- Juzzio is a BETA app built by an independent developer (Engin ÇIRPAN).
- Contact and requests: engiincr@pm.me
- In the app: Settings → Help & Support → Report a bug / Feedback

## 2. Short summary (most asked)

- **We do not sell, rent or share your personal data** with ad networks. The app contains no advertising, analytics or tracking libraries.
- **We have no access to your card or bank details.** The app contains no payment, card, bank or wallet code, and no screen asks for such information.
- **The camera and microphone are never used without permission.** They are only used after you grant the Android permission, and only for calls you start or accept, the story/post camera and voice message recording. Calls are not recorded.
- **Your contacts and SMS are never read.** Location is read only for actions you start, with your permission: sending your location in a chat, Safety Check (SOS) and the sunset mode of Eye Comfort. Location is never tracked in the background.
- **In 1:1 chats, messages, photos, videos, voice messages, documents, locations and story replies are end-to-end encrypted**, using post-quantum hybrid encryption since v0.8.0. The server and administrators cannot see this content.
- **Chat backup is optional** and lives in your own Google Drive account, encrypted with a password only you know. We cannot read it.

## 3. Data processed and purposes

| Data | Purpose | Legal basis (KVKK Art. 5 / GDPR Art. 6) |
| :-- | :-- | :-- |
| Email, username, name, profile photo, bio | Account creation, sign-in, profile | Performance of contract |
| Messages, photos, videos, voice messages, stories, posts | Messaging and sharing | Performance of contract |
| Call records (who, when, duration, status) | Call history, missed call notifications | Performance of contract |
| Notification (FCM) token, device ID | Sending notifications, abuse and ban enforcement | Legitimate interest |
| Language, theme, privacy and sound preferences | App settings | Performance of contract |
| Violation records (explicit content detection) | Community safety | Legitimate interest |
| Bug reports (text, optional screenshot, version, OS) | Fixing bugs | Explicit consent (you send them) |
| Automatic crash reports (error type, masked stack trace, version, OS) | App stability | Legitimate interest (can be turned off in Settings) |
| Daily translation/transcription count (a number only, never content) | Cost and abuse control | Legitimate interest |

## 4. End-to-end encryption (v0.8.0 · post-quantum hybrid)

- 1:1 messages are encrypted on your device with a key derived from a **X25519 + ML-KEM-768 (NIST FIPS 203)** hybrid key exchange, using **HKDF-SHA256** and **AES-256-GCM**. A message can only be opened if both the classical and the post-quantum method are broken, which protects against "Harvest Now, Decrypt Later" attacks.
- **Key rotation:** a new session key every 50 messages or 24 hours, and a new identity key every 30 days. Every message is encrypted with its own key.
- Private keys stay only in your phone's secure storage (Android Keystore) and are never sent to the server.
- The server only stores ciphertext and public keys; notification previews are sent as "🔒 Encrypted message".
- Update files are integrity-checked with SHA-256; the app contains ML-DSA (FIPS 204) release signature verification.
- **Media:** in 1:1 chats, photos, videos (up to 40 MB), voice messages, documents (including the file name) and story replies are encrypted on your device with a random per-file key using **AES-256-GCM**. The key and a **SHA-256** integrity hash travel inside the encrypted message. If encryption fails, nothing is sent; if the integrity check fails, nothing is shown.
- **Scheduled messages:** in 1:1 chats, scheduled messages are encrypted on your device and wait on the server only in encrypted form.
- **Limits:** group messages, group polls and media in group chats are not yet end-to-end encrypted (they are encrypted in transit with TLS and stored in private storage that only group members can access). Automatic translation is **on by default**; while it is on, the text of a message is sent from your device to the translation service (Google Translate) for translation, while it remains encrypted on the server. You can turn it off in Settings → Privacy. Sign-in uses Supabase's standard session tokens.

## 4a. Security Center, devices and security events (v0.9.0)

- Devices linked to your account are shown to you with only the last 6 characters of the device ID. New device sign-ins, device removals and encryption key changes are recorded by the server as **security events**. Only you can see these records; the app cannot write or change them.
- These records are deleted when your account is deleted.

## 4b. Chat backup (Google Drive)

- You can optionally create a backup from Settings → Back up messages / chats.
- The backup is written to the **hidden app folder** (appDataFolder) in the Google Drive of the account you choose. Juzzio only requests access to this folder and cannot see your other Drive files.
- The content is encrypted with **AES-256-GCM** using a key derived with **Argon2id** from a password of at least 8 characters that you choose. The password is never sent or stored anywhere; if you forget it, the backup cannot be opened.
- The backup is tied to your account ID; if the account is deleted and recreated, the old backup will not load.

## 4c. Offline cache on your device (v0.9.2)

- So you can read without internet, the last 300 messages of each chat, photos you viewed, profile pictures and voice messages you listened to are stored **only on this device**, in an app folder reserved for your account.
- End-to-end encrypted messages and media stay **encrypted** on the device and are only decrypted in memory while shown.
- The cache is deleted when you sign out or delete your account. Since v0.9.7 the media cache limit is set by the administrator (default 300 MB); you can clear it in Settings → Storage → Clear cache (your messages and account are not deleted).

## 4d. Notification translation and beauty filter (v0.9.3)

- Incoming message notifications are translated into your app language. For end-to-end encrypted messages, the text is first decrypted **on your device**; translation works like in-chat translation, sending only that text to the translation service (Google Translate). If you turn off notification previews in Settings → Notifications, content is neither shown nor translated.
- Beautification in video calls and story photos runs entirely **on your device**; no face data is extracted, stored or sent.

## 4e. Location, documents and shifts (v0.9.4)

- **Location** is read once, with your permission, only when you tap "Location" in a chat, and is sent as a message; it is never tracked in the background. In 1:1 chats, location messages are end-to-end encrypted.
- **Documents** (PDF, ZIP, DOCX …) in 1:1 chats are stored end-to-end encrypted together with their file name; the server cannot see the content or the name. Documents in group chats are kept in private storage accessible only to group members.
- Your **shift plan** is visible only to you; if you share it with a group, only that group's members can see it.
- The app reads the server time to verify your device clock; this sends no personal data.

## 4f. Safety Check, view-once media, question box, badges (v0.9.5)

- **Safety Check (SOS):** only when you start it, and while the app is open, your location and battery level are written to the server once a minute and are visible only to members of the chat you selected. No new location is written once it ends. Alert notifications include the last location link. In an emergency, call your official emergency number; Juzzio is not an emergency service.
- **View-once media:** once the recipient opens and closes it (or 5 minutes after opening, or 14 days if never opened) the file is permanently deleted from the server. Screenshots are blocked on Android while viewing; photographing the screen with another device cannot be prevented.
- **Anonymous question box:** the identity of an anonymous asker is never shown to the box owner. In an abuse report, only authorized staff can see the sender, and that access is logged.
- **Badges, streaks and trust score:** the days you open the app and the days you feed your chick count toward streaks. The trust score is calculated with transparent rules from account age, distinct reporters in the last 30 days and violations in the last 90 days, and is used only for moderation.
- **Watch Party:** the video link you share and the playback position are visible only to members of that chat.

## 4g. Crash reports, Eye Comfort, encrypted media (v0.9.6)

- **Automatic crash reports:** when the app crashes or an error occurs, the error type, stack trace (where in the code it happened), app version, platform and OS version are sent to the server. Message content is never sent; email addresses, phone numbers, long digit sequences, session tokens and link parameters are masked on the device before sending. Only authorized administrators can see them; records are deleted after 90 days. You can turn off "Send crash reports automatically" in Settings.
- **Eye Comfort:** in "Sunset to sunrise" mode your location is read once, rounded to city level (~1 km), and stored only on your device; it is never sent to the server.
- **Voice messages, videos and story replies in 1:1 chats** are end-to-end encrypted. Voice message transcription happens only if you turned on "translation in encrypted chats", using a temporary copy that is uploaded for the transcription and deleted immediately.
- **AI usage counter:** for cost control, the number of your daily translations/transcriptions is counted (a number only, not content).
- **Legal requests:** when there is an official request, only the super administrator can export your profile, device, post, report and audit records, together with the reason, and this export is logged. End-to-end encrypted message content does not exist on the server and therefore cannot be included.

## 4h. Local SQLite cache, media cache and interface (v0.9.7)

- **Local database for instant launch:** the chat list, profiles and the last 300 messages of each chat are kept in an SQLite database (Drift) on your device, reserved for your account. End-to-end encrypted messages are written to this database **encrypted** as well and are only decrypted while shown on screen. The database is deleted when you sign out.
- **Media cache:** the on-device cache limit for media you viewed (default 300 MB) and the maximum file age (default 60 days) are set by the administrator; when exceeded, the files you have not opened for the longest time are removed automatically from your device. This setting sends no personal data to the server.
- **Notification stack, theme transitions and cloth refresh** run entirely on your device and collect no new data.
- **Call power profile:** in the background or on a weak network, video quality is temporarily reduced to 360p; no additional data is processed for this.

## 5. Service providers that receive data

The following services are used to run Juzzio. Some are located abroad, so data may be transferred abroad (KVKK Art. 9).

- **Supabase** (database, file storage, authentication): account, message and media data.
- **LiveKit Cloud** (voice/video call server): audio and video streams during calls. Nothing is recorded.
- **Deepgram** (speech-to-text): your own voice is sent for captions only when someone **speaking a different language** is in the call or when you turn on live translation yourself. No audio is sent between people speaking the same language.
- **Google** – Firebase Cloud Messaging (notifications); Google Translate (automatic translation, from the device); optional Google Cloud Vision (only for explicit content checks in video calls; frames are not stored).
- **MyMemory** (fallback translation if Google Translate fails).
- **Apple iTunes Search** (the song name you type in the add-music screen is searched and a 30-second preview is played).
- **GitHub** (app updates and release notes).

## 6. What administrators can and cannot see

- Can see: the user list and emails, call record summaries, reports, bug and crash reports; they can delete content, close accounts and issue penalties.
- Cannot see: end-to-end encrypted message and media content, your password, card/bank details (there are none). There is no free-form SQL console in the admin panel; critical actions such as legal export and signing everyone out are limited to the super administrator and recorded in the audit log.
- Unencrypted content (group messages, group media) is technically readable in the database; the admin panel has no feature that displays message content.

## 7. Retention periods

- Data is kept while your account is open. If you turn on disappearing messages, messages are deleted after the period you choose.
- Stories disappear after 24 hours.
- You can delete your account (Settings → Account). Media files of deleted messages, stories and accounts are queued for automatic deletion and removed from storage on the server. Automatic crash reports are deleted after 90 days.

## 8. Security measures

- All connections are encrypted with HTTPS/TLS.
- Row-level security (RLS) in the database: users can only see chats they are a member of.
- Media folders can no longer be listed by anyone (v0.6.1).
- Updates are downloaded only from the official GitHub release; Android does not allow installing an APK with a different signature over the app.
- The source code contains no secret keys; an automatic secret scan runs on every push to GitHub, and a strict `.gitignore` keeps keys, certificates, local databases and build outputs out of the repository.
- Unauthorized access, attacks and reverse engineering attempts are logged and legal action is taken (see Terms of Use, section 8).

## 9. Your rights (KVKK Art. 11 and GDPR)

You have the right to learn whether your personal data is processed, request information about it, learn its purpose, know who it is transferred to, request correction of incomplete or inaccurate data, request its deletion or destruction, object, and claim compensation for damages. Send your requests to engiincr@pm.me; they are answered within 30 days at the latest. If you are in the European Union, your GDPR rights of access, rectification, erasure, portability and objection also apply.

## 10. Children

Juzzio is not designed for children under 13.

## 11. Changes

Changes to this policy are announced in the in-app "Release notes" section and on GitHub.
