"""Eski şerit-J ikon üreticisi yerine geçer (v2.1): tüm ikonlar artık resmî logodan üretilir.
Geriye dönük uyumluluk için `render(size, mode)` korunur ve tools/brand_logo.py'yi kullanır.
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand_logo as bl  # noqa: E402


def render(size, mode="legacy"):
    src = Image.open(bl.SRC)
    g, _ = bl.glyph(src)
    if mode == "legacy":
        return bl.place(g, size, 0.62, bl.BG, 0.24)
    if mode == "background":
        return Image.new("RGB", (size, size), bl.BG)
    if mode == "monochrome":
        w, _ = bl.glyph(src, (255, 255, 255))
        return bl.place(w, size, 0.42)
    return bl.place(g, size, 0.42)


def main():
    bl.main()


if __name__ == "__main__":
    main()
