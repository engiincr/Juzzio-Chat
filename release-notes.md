# Juzzio v1.2.3 — Simpler Sign-up Consent (per KVKK 2026 guidance)

## 🎯 Why did this update come?

The four separate consent boxes on the sign-up and sign-in screen were reduced to two, in line with the Turkish Data Protection Board's Principle Decision No. 2026/347 (privacy notice and consent kept separate, no consent taken in the notice) and the 2024 amendment of KVKK Art. 9 (continuous transfers abroad rely on standard contracts). Tapping the box opens the text automatically; scroll to the end, tap "I have read and understood" and sign-up or sign-in completes.

## ✨ What's new?

- ✅ Only two boxes: (1) required — "I accept the Terms of Use and confirm I am over 15. I have read and understood the Privacy Notice." (2) optional — news and campaign e-mails
- 📖 Tapping the box opens the Privacy Notice and Terms; "Scroll to end" takes you to the bottom, where "I have read and understood" becomes active and ticks the box
- 🚀 Tapping "Sign up" / "Sign in" without the tick opens the text automatically; after confirming, the action continues and completes
- 📧 Marketing consent opens its own text, is never pre-ticked and is given with "I agree"

## 🛠️ What was fixed?

- Privacy Notice rewritten with every element required by the Turkish notice regulation: controller, data, collection method, purposes and legal bases, recipients, basis for transfers abroad, retention, rights, how to apply and the right to complain to the Board
- Removed the separate "consent to cross-border transfer": continuous transfers rely on appropriate safeguards (standard contracts) under KVKK Art. 9 and are explained in the notice
- Age requirement added to the Terms (15+, under 18 with a parent's or guardian's knowledge); Privacy Policy children and rights sections updated
- Existing users see the updated texts once

## 🔒 Security & privacy

- The server only requires the mandatory statement (terms + age 15+ + notice read); cross-border consent is no longer required
- Consent records keep version, time and app version (no IP); clients cannot write the consent columns directly

