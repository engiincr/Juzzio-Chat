#!/usr/bin/env python3
"""Yasal metinler → lib/core/legal_texts.dart (uygulama içi).

v0.9.7: GitHub sayfaları İngilizce; Türkçe (KVKK) metinler docs/legal/tr/ altında.
  • Türkçe : docs/legal/tr/PRIVACY.md, TERMS.md, LICENSE.txt → kJuzzioPrivacyMd, kJuzzioTermsMd, kJuzzioLicenseText
  • English: PRIVACY.md, TERMS.md, LICENSE (depo kökü)      → kJuzzioPrivacyMdEn, kJuzzioTermsMdEn, kJuzzioLicenseTextEn
Uygulama dili Türkçe ise Türkçe, değilse İngilizce gösterilir. Metin değişince bu betik
yeniden çalıştırılır (CI kapısı `--check` ile üretilmiş dosyanın güncel olduğunu doğrular)."""
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rd(n):
    with open(os.path.join(root, n), encoding='utf-8') as f:
        t = f.read()
    assert "'''" not in t, n
    return t


SOURCES = (
    ("docs/legal/tr/PRIVACY.md", "kJuzzioPrivacyMd"),
    ("docs/legal/tr/TERMS.md", "kJuzzioTermsMd"),
    ("docs/legal/tr/LICENSE.txt", "kJuzzioLicenseText"),
    ("PRIVACY.md", "kJuzzioPrivacyMdEn"),
    ("TERMS.md", "kJuzzioTermsMdEn"),
    ("LICENSE", "kJuzzioLicenseTextEn"),
)

out = ["// Otomatik üretildi: scripts/gen_legal.py — elle düzenlemeyin.", ""]
for name, var in SOURCES:
    out.append(f"const String {var} = r'''{rd(name)}''';")
    out.append("")
text = "\n".join(out)
target = os.path.join(root, "lib/core/legal_texts.dart")
if "--check" in sys.argv[1:]:
    cur = open(target, encoding="utf-8").read() if os.path.exists(target) else ""
    if cur != text:
        print("::error file=lib/core/legal_texts.dart::Yasal metinler güncel değil — `python3 scripts/gen_legal.py` çalıştırın.")
        sys.exit(1)
    print("legal_texts.dart güncel ✅")
    sys.exit(0)
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
print("legal_texts.dart üretildi")
