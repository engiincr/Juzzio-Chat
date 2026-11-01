#!/usr/bin/env python3
"""Juzzio v0.8.0 — ML-DSA-65 (NIST FIPS 204) yayın imzası anahtar çifti üretir.

Kullanım (kendi bilgisayarınızda, bir kez):
    pip install "cryptography>=46"
    python3 scripts/mldsa_keygen.py

Çıktı:
  ML_DSA_SEED        → GitHub › Settings › Secrets › Actions  (GİZLİ! kimseyle paylaşmayın)
  ML_DSA_PUBLIC_KEY  → GitHub › Settings › Variables › Actions (açık anahtar, gizli değil)
Dosyaya hiçbir şey yazılmaz.
"""
import base64
import os

from cryptography.hazmat.primitives.asymmetric import mldsa
from cryptography.hazmat.primitives import serialization

seed = os.urandom(32)
sk = mldsa.MLDSA65PrivateKey.from_seed_bytes(seed)
pk = sk.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
print("ML_DSA_SEED=" + base64.b64encode(seed).decode())
print("ML_DSA_PUBLIC_KEY=" + base64.b64encode(pk).decode())
