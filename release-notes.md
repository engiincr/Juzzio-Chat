# Juzzio v1.0.0 — Juzzio Space: New Design & Instant Messaging

## 🎯 Why did this update come?

Juzzio moves to the "Juzzio Space" interface designed in Figma: deep theme gradients, frosted glass cards and a glowing accent in every theme. In the same update messages send without waiting, location/link/poll experiences were rebuilt, shifts can be planned by date range and admin logs became readable.

## ✨ What's new?

- 🎨 Juzzio Space design: "Your space · Juzzio." header, search with a ⌘K shortcut, story rings, Inbox · Messages, filter pills with counters, glass chat cards and a floating glass bottom bar
- 🌈 All 16 themes share the same design language; accent, background depth and glass opacity come from the selected theme (Emerald is the default for new users)
- 🪪 Profile and admin panel use the Juzzio Space layout too: large header, square avatar with a glowing ring, glass counter tiles, accent primary button, capsule tabs and glass stat cards
- ⚡ Messages send instantly: the bubble appears right away, translation runs in the background and shows up under the message when ready (in end-to-end encrypted chats the translation is added encrypted too)
- 📍 Shared locations appear as a card with a map preview and open in Google Maps on Android, Apple Maps on iOS, or Google Maps
- 🔗 Links, e-mail addresses and phone numbers in messages, bios, posts and comments are tappable and open in the default browser/app
- 📊 New poll card: options with share bars, percentages, winner highlight and a live status chip
- 📅 Date ranges in the shift planner: pick start–end days and hours (overnight shifts included), filter weekdays/weekends, share with a group and post a plan summary automatically
- 🐣 When petted, the chick twirls to the right like a princess, winks and flirts; the chick badge in chats does the same animation
- 👑 New chick customizations: princess tiara, flower crown, wizard hat, star glasses, princess tutu, pearl necklace, ballet shoes, Castle/Space/Sakura scenes
- 🧾 Admin logs are readable sentences in the admin's language: who did what, to whom and when (no raw codes or IDs)

## 🛠️ What was fixed?

- Cloth pull-to-refresh fixed on mobile: no more conflict with Android's stretch overscroll or iOS bouncing, and short lists can be pulled too
- Removed the GPU blur artifact on the hand shadow (rectangular smudge/flicker); a soft radial shadow is used instead
- Chat ⋯ menu cleaned up: no emojis, icons and an opaque (readable) background, destructive actions separated in red
- Menus, bottom sheets and dialogs are now nearly opaque — text stays readable

## 🔒 Security & privacy

- The link opener only allows http/https/mailto/tel/geo (javascript:, file: etc. are rejected)
- Background translation keeps end-to-end encryption: in encrypted chats the translation is attached as a separate encrypted payload

