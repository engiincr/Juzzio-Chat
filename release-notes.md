# Juzzio v0.9.9 — Cloth Refresh: Pixel-Faithful 3D Revision

## 🎯 Why did this update come?

The v0.9.8 cloth refresh preview was compared frame by frame with the reference video and 11 visual/timing deviations were found. This update fixes the 3D hand, fabric folds, notch layering and page sync to match all 11 points exactly.

## ✨ What's new?

- ⚫ The Dynamic Island is pure black (#000000) in both themes and always on the top layer; the hand is masked at the island's bottom edge, emerges from it and disappears back into it
- 👀 On the first pull (0–35 px) only the 4 chubby fingertips and nails peek out from under the island; the hand and wrist come down as you keep pulling
- 🖐️ A shorter, chubbier 3D clay arm (wrist ≈ 55% of the island width), glossy 3D nails on every finger including the thumb, knuckle creases and a warm matte peach skin (#F2C2B3 / #DF9F8E / #F9DCD3)
- 🕰️ During the pendulum the root stays fixed at the island while the arm and wrist bend like a flexible bone; at the +25° peak the fingers fan out, then close again on the way back (9 separate 3D poses)
- ✊ The fist clearly shows the 4 curled fingers' knuckles, vertical shadow grooves between them and the thumb clenched underneath
- 🦋 When the fist closes, butterfly-wing pinch folds curl up toward the island on its left and right; the bottom stays smooth
- 🧵 On the yank, 6 curved, asymmetric 3D drapery pleats cover the search icon, location title and avatar like a semi-transparent sheet and reach down to "Popular Food"
- 📏 The content moves 140–155 px down while pulling and swinging, so the hand swings in clean empty space without touching any text or icon
- 🔒 The page stays locked at the fully pulled position until the fist grabs the fabric; only during the yank does it rise, attached to the fist's lower edge at the same speed as the hand
- 🧺 In the last 250 ms the folds stretch upward and flatten, and the page settles with no jitter

## 🛠️ What was fixed?

- Removed the black/dark grey "sunburst" lines in light mode: valleys are only silver grey (#DFE2E8–#C8CDD6), ridges pure white
- Removed the white haze around the fist in dark mode: valleys #07080B, ridges #222630
- The hand no longer paints over the notch; the grey notch in dark mode is fixed
- Removed the rigid single-sprite arm rotation
- Fixed the page jumping up early while the fist was still closing
- The APK build failed on a dependency conflict (file_picker <12 needs win32 ^5, flutter_secure_storage ^11 needs win32 ^6); file_picker was upgraded to ^13 and the encrypted key store was left untouched

## 🔒 Security & privacy

- The new visuals are fully original 3D renders made by us; no extra permissions or data collection

## ⬇️ Download

- Latest: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- This version: `juzzio-v0.9.9-release.apk` (109.66 MB)

## ✅ Verify the APK

```bash
sha256sum Juzzio-latest.apk
# f7430231486e23c28c47bab9eafa8991dd9310c07bd43e84e8a157699f1da552  Juzzio-latest.apk
```

Built: 2026-11-09 12:28 UTC — GitHub Actions
