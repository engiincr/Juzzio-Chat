#!/usr/bin/env python3
"""Juzzio v0.8.0 — version.json'u ML-DSA-65 (FIPS 204) ile imzalar.

İmzalanan ileti: "juzzio-release|<version>|<build>|<apkSha256>" (bağlam: "juzzio-release").
Uygulama, ML_DSA_PUBLIC_KEY ile derlendiyse imzası geçersiz veya eksik sürümü
güncelleme olarak göstermez (sahte version.json / APK değiştirme saldırısına karşı).
ML_DSA_SEED ortam değişkeni yoksa sessizce atlanır.
"""
import base64
import json
import os
import sys

seed_b64 = os.environ.get("ML_DSA_SEED", "").strip()
if not seed_b64:
    print("ML_DSA_SEED yok, imza atlandı")
    sys.exit(0)
from cryptography.hazmat.primitives.asymmetric import mldsa  # noqa: E402

path = sys.argv[1] if len(sys.argv) > 1 else "version.json"
with open(path, encoding="utf-8-sig") as f:
    data = json.load(f)
msg = "juzzio-release|{}|{}|{}".format(
    str(data.get("version", "")).strip(),
    int(data.get("build") or data.get("buildNumber") or data.get("versionCode") or 0),
    str(data.get("apkSha256", "")).strip().lower(),
).encode()
sk = mldsa.MLDSA65PrivateKey.from_seed_bytes(base64.b64decode(seed_b64))
sig = sk.sign(msg, b"juzzio-release")
data["mldsa65Sig"] = base64.b64encode(sig).decode()
data["signatureAlg"] = "ML-DSA-65 (FIPS 204)"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("version.json ML-DSA-65 ile imzalandı")
