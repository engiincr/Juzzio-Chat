#!/usr/bin/env python3
"""Juzzio — push öncesi kaynak bütünlük kontrolü.

Zip eski bir klasörün üstüne açılırsa eski ve yeni dosyalar karışır ve GitHub'da
derleme yüzlerce hatayla düşer. Bu betik lib/, test/, pubspec.yaml ve iş akışını
juzzio_manifest.json'daki SHA-256 değerleriyle karşılaştırır:
  • manifestte olmayan eski .dart dosyalarını siler (bunlar derlemeyi bozar),
  • içeriği farklı/eksik dosya varsa push'u DURDURUR ve listeler.
Bilerek kod değiştirdiyseniz: python scripts/verify_tree.py --update
"""
import hashlib, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAN = os.path.join(ROOT, "juzzio_manifest.json")
DIRS = ("lib", "test")
EXTRA = ("pubspec.yaml", ".github/workflows/android-ci.yml")


def tracked():
    out = []
    for d in DIRS:
        for base, _, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                if f.endswith(".dart"):
                    out.append(os.path.relpath(os.path.join(base, f), ROOT).replace(os.sep, "/"))
    out += [e for e in EXTRA if os.path.exists(os.path.join(ROOT, e))]
    return sorted(out)


def sha(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        data = fh.read().replace(b"\r\n", b"\n")  # Windows satır sonları fark sayılmaz
    return hashlib.sha256(data).hexdigest()


def main():
    if "--update" in sys.argv:
        json.dump({r: sha(r) for r in tracked()}, open(MAN, "w"), indent=0, sort_keys=True)
        print("juzzio_manifest.json güncellendi")
        return 0
    if not os.path.exists(MAN):
        print("[UYARI] juzzio_manifest.json yok; kontrol atlandı")
        return 0
    man = json.load(open(MAN))
    removed, bad = [], []
    for rel in tracked():
        if rel.endswith(".dart") and rel not in man:
            os.remove(os.path.join(ROOT, rel)); removed.append(rel)
    for rel, h in man.items():
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            bad.append("EKSİK   " + rel)
        elif sha(rel) != h:
            bad.append("FARKLI  " + rel)
    for r in removed:
        print("[TEMİZLENDİ] eski dosya silindi:", r)
    if bad:
        print("[HATA] Proje dosyaları karışmış (eski sürüm dosyaları var):")
        for b in bad[:60]:
            print("   ", b)
        print("Çözüm: zip'i BOŞ, YENİ bir klasöre çıkarın ve push'u oradan yapın.")
        print("Kodu bilerek değiştirdiyseniz: python scripts/verify_tree.py --update")
        return 1
    print("[OK] Kaynak bütünlüğü doğrulandı (%d dosya)" % len(man))
    return 0


if __name__ == "__main__":
    sys.exit(main())
