#!/usr/bin/env python3
"""Juzzio 2.1 marka ikonu: yeşil şerit "J" (kodla çizilir; dış görsel kullanılmaz).

Aynı geometri lib/widgets/juzzio_brand.dart içindeki JuzzioLogoGlyph ile paylaşılır.
Çıktı: Android başlatıcı ikonları (eski + uyarlanabilir ön/arka plan + tek renk).
Kullanım: python3 tools/brand_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
BG = (14, 15, 18)
LIME = (198, 241, 53)
LIME_HI = (226, 255, 120)
DEEP = (46, 74, 8)


def bezier(p0, p1, p2, p3, n=400):
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        yield (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1])


def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


# Birim kare içinde şerit yolları (Dart tarafıyla aynı)
STEM = [(0.64, 0.17), (0.64, 0.40), (0.64, 0.56)]
HOOK = list(bezier((0.64, 0.56), (0.64, 0.86), (0.36, 0.90), (0.24, 0.70)))
LEAF = list(bezier((0.24, 0.40), (0.34, 0.30), (0.50, 0.20), (0.64, 0.17)))
WIDTH = 0.19


def draw_glyph(img, box, mono=None):
    x0, y0, size = box
    d = ImageDraw.Draw(img)
    r = WIDTH * size / 2

    def stroke(points, colors):
        n = len(points)
        for i, (px, py) in enumerate(points):
            col = mono or colors(i / max(1, n - 1))
            cx, cy = x0 + px * size, y0 + py * size
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + ((255,) if len(col) == 3 else ()))

    # yaprak (arka kat, koyu → limon)
    stroke(LEAF, lambda t: lerp(DEEP, LIME, t))
    # gövde + kanca (ön kat, parlak limon → gölgeli kıvrım)
    path = []
    for a, b in zip(STEM, STEM[1:]):
        for k in range(160):
            path.append((a[0] + (b[0] - a[0]) * k / 160, a[1] + (b[1] - a[1]) * k / 160))
    path += HOOK
    def body(t):
        if t < 0.5:
            return lerp(LIME_HI, LIME, t * 2)
        if t < 0.78:
            return lerp(LIME, DEEP, (t - 0.5) / 0.28 * 0.55)
        return lerp(lerp(LIME, DEEP, 0.55), LIME, (t - 0.78) / 0.22)
    stroke(path, body)


def render(size, mode):
    ss = 4
    big = size * ss
    if mode == "legacy":
        img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.24), fill=BG + (255,))
        draw_glyph(img, (big * 0.12, big * 0.12, big * 0.76))
    elif mode == "background":
        img = Image.new("RGB", (big, big), BG)
        return img.resize((size, size), Image.LANCZOS)
    else:  # foreground / monochrome: 108dp içinde 66dp güvenli alan
        img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        inner = big * 0.56
        off = (big - inner) / 2
        draw_glyph(img, (off, off, inner), mono=(255, 255, 255) if mode == "monochrome" else None)
    return img.resize((size, size), Image.LANCZOS)


def main():
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, s in legacy.items():
        folder = os.path.join(RES, f"mipmap-{dpi}")
        render(s, "legacy").save(os.path.join(folder, "ic_launcher.png"))
        a = int(s * 108 / 48)
        render(a, "background").save(os.path.join(folder, "ic_launcher_background.png"))
        render(a, "foreground").save(os.path.join(folder, "ic_launcher_foreground.png"))
        render(a, "monochrome").save(os.path.join(folder, "ic_launcher_monochrome.png"))
    os.makedirs(os.path.join(ROOT, "assets", "brand"), exist_ok=True)
    render(512, "legacy").save(os.path.join(ROOT, "assets", "brand", "juzzio_mark_512.png"))
    print("ikonlar üretildi")


if __name__ == "__main__":
    main()
