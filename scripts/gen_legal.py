#!/usr/bin/env python3
"""PRIVACY.md / TERMS.md / LICENSE → lib/core/legal_texts.dart (uygulama içi yasal metinler).
Tek kaynak: depodaki Markdown dosyaları. Metin değişince bu betik yeniden çalıştırılır."""
import os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(n):
    with open(os.path.join(root, n), encoding='utf-8') as f:
        t = f.read()
    assert "'''" not in t
    return t
out = ["// Otomatik üretildi: scripts/gen_legal.py — elle düzenlemeyin.", ""]
for name, var in (("PRIVACY.md", "kJuzzioPrivacyMd"), ("TERMS.md", "kJuzzioTermsMd"), ("LICENSE", "kJuzzioLicenseText")):
    out.append(f"const String {var} = r'''{rd(name)}''';")
    out.append("")
with open(os.path.join(root, "lib/core/legal_texts.dart"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("legal_texts.dart üretildi")
