#!/usr/bin/env python3
"""v0.7.0 — Hassas bilgi koruması: depoya (README ve tüm .md dahil) gizli anahtar,
token, şifre veya kişisel kimlik bilgisi girmesini engeller. CI'da her gönderimde ve
push.bat/push.sh içinde gönderimden önce çalışır. Bulursa hatayla durur.

Kullanım: python3 scripts/check_secrets.py
"""
import re
import subprocess
import sys

RULES = [
    ("Google API anahtarı", r"AIza[0-9A-Za-z_\-]{35}"),
    ("GitHub token", r"(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    ("Supabase gizli anahtarı", r"sb_secret_[A-Za-z0-9_\-]{20,}"),
    ("JWT (service_role vb.)", r"eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,}"),
    ("Özel anahtar", r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ("Deepgram anahtarı (40 hex, Token)", r"(?i)token\s+[0-9a-f]{40}\b"),
    ("Gizli değişken ataması", r"(?i)(api[_-]?secret|livekit[_-]?api[_-]?secret|deepgram[_-]?api[_-]?key|service[_-]?role[_-]?key|storePassword|keyPassword)\s*[:=]\s*['\"]?[A-Za-z0-9_\-/+]{12,}"),
    ("TC kimlik / IBAN", r"\bTR\d{2}\s?(\d{4}\s?){5}\d{2}\b"),
]
ALLOW = ("scripts/check_secrets.py", ".github/workflows/android-ci.yml")
SKIP_EXT = (".png", ".jpg", ".jpeg", ".webp", ".ogg", ".ttf", ".otf", ".jks", ".keystore", ".apk", ".zip")


def main() -> int:
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split()
    bad = 0
    for f in files:
        if f in ALLOW or f.lower().endswith(SKIP_EXT):
            continue
        try:
            text = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for name, rx in RULES:
            for m in re.finditer(rx, text):
                line = text.count("\n", 0, m.start()) + 1
                # yer tutucular (örn. ${{ secrets.X }}, <...>, ****) serbest
                frag = m.group(0)
                if "secrets." in frag or "<" in frag or "***" in frag or "YOUR_" in frag:
                    continue
                print(f"::error file={f},line={line}::{name} bulundu — depoya gizli bilgi eklenemez. Anahtarı iptal edip yenileyin.")
                bad += 1
    if bad:
        print(f"{bad} hassas bilgi bulundu.")
        return 1
    print("Hassas bilgi taraması temiz ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
