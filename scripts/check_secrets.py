#!/usr/bin/env python3
"""v0.7.0 — Hassas bilgi koruması: depoya (README ve tüm .md dahil) gizli anahtar,
token, şifre veya kişisel kimlik bilgisi girmesini engeller. CI'da her gönderimde ve
push.bat/push.sh içinde gönderimden önce çalışır. Bulursa hatayla durur.

Kullanım:
  python3 scripts/check_secrets.py            → izlenen dosyaların güncel içeriği
  python3 scripts/check_secrets.py --history  → TÜM Git geçmişi (her commit'in eklediği satırlar)

v0.9.0: --history kipi eklendi; yalnızca güncel ağacı taramak, geçmiş commit'lere
gömülü kalmış bir anahtarı yakalamaz. Eşleşen değer ASLA yazdırılmaz.
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


def _is_placeholder(frag: str) -> bool:
    # yer tutucular (örn. ${{ secrets.X }}, <...>, ****) serbest
    return "secrets." in frag or "<" in frag or "***" in frag or "YOUR_" in frag


def scan_history() -> int:
    """Her commit'in eklediği satırları tarar (silinmiş anahtarlar dahil)."""
    proc = subprocess.run(
        ["git", "log", "--all", "-p", "--no-color", "--no-ext-diff", "-U0", "--format=commit %H"],
        capture_output=True, text=True, errors="ignore", check=True,
    )
    bad = 0
    commit, path = "", ""
    for raw in proc.stdout.splitlines():
        if raw.startswith("commit "):
            commit = raw[7:19]
            continue
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else raw[4:]
            continue
        if not raw.startswith("+") or raw.startswith("+++"):
            continue
        if path in ALLOW or path.lower().endswith(SKIP_EXT):
            continue
        line = raw[1:]
        for name, rx in RULES:
            for m in re.finditer(rx, line):
                if _is_placeholder(m.group(0)):
                    continue
                print(f"::error file={path}::{name} Git geçmişinde bulundu (commit {commit}) — anahtarı iptal edip yenileyin.")
                bad += 1
    if bad:
        print(f"{bad} hassas bilgi Git geçmişinde bulundu.")
        return 1
    print("Git geçmişi hassas bilgi taraması temiz ✅")
    return 0


def main() -> int:
    if "--history" in sys.argv[1:]:
        return scan_history()
    files = subprocess.run(["git", "ls-files", "-z"], capture_output=True, text=True, check=True).stdout.split("\0")
    bad = 0
    for f in files:
        if not f or f in ALLOW or f.lower().endswith(SKIP_EXT):
            continue
        try:
            text = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for name, rx in RULES:
            for m in re.finditer(rx, text):
                line = text.count("\n", 0, m.start()) + 1
                if _is_placeholder(m.group(0)):
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
