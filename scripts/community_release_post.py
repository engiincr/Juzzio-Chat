#!/usr/bin/env python3
"""Juzzio v1.2.0 — Juzzio Topluluğu sürüm duyurusu metni.

version.json'daki sürüm, başlık ve ayrıntılardan (neden / yenilikler / düzeltmeler)
TR ve EN duyuru metni üretir; CI bunu public.juzzio_community_post_release()'e verir.
Fonksiyon aynı sürümü iki kez paylaşmaz (idempotent).

Kullanım: python3 scripts/community_release_post.py <ver|tr|en>
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build(lang: str, data: dict) -> str:
    ver = data.get("version", "")
    title = data.get("releaseTitle" if lang == "tr" else "releaseTitleEn") or data.get("releaseTitle", "")
    det = (data.get("details") or {}).get(lang) or {}
    head = f"🚀 Juzzio v{ver} yayında!" if lang == "tr" else f"🚀 Juzzio v{ver} is out!"
    out = [head]
    if title:
        out.append(title)
    reason = det.get("reason") or (data.get("changelog") or {}).get(lang, "")
    if reason:
        out += ["", reason]
    feats = det.get("features") or []
    if feats:
        out += ["", "✨ Yenilikler" if lang == "tr" else "✨ What's new"]
        out += [f"• {f}" for f in feats[:12]]
    fixes = det.get("fixes") or []
    if fixes:
        out += ["", "🛠 Düzeltmeler" if lang == "tr" else "🛠 Fixes"]
        out += [f"• {f}" for f in fixes[:8]]
    out += ["", "Güncellemek için: Ayarlar → Güncellemeler" if lang == "tr" else "To update: Settings → Updates"]
    return "\n".join(out)[:3900]


def main() -> int:
    with open(os.path.join(ROOT, "version.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    what = sys.argv[1] if len(sys.argv) > 1 else "tr"
    if what == "ver":
        print(data.get("version", ""))
    else:
        print(build("en" if what == "en" else "tr", data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
