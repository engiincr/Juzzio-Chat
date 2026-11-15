#!/usr/bin/env python3
"""Hava teması ve Ay evresi için GERÇEKÇİ görseller — tamamen kodla üretilir (telifsiz, Juzzio'ya ait).
Stok fotoğraf/NASA görseli KULLANILMAZ. Çıktı: assets/weather/{moon,cloud_a,cloud_b,sun}.png
Kullanım: python3 tools/weather_sprites.py"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'assets/weather')
rng = np.random.default_rng(1299)

def fbm(n, octaves=6, base=4):
    """Kesirli gürültü 0..1 (bilinear büyütülmüş rastgele ızgaraların toplamı)."""
    out = np.zeros((n, n)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        g = base * (2 ** o)
        a = rng.random((g + 1, g + 1)).astype(np.float32)
        im = Image.fromarray((a * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        out += np.asarray(im, dtype=np.float32) / 255.0 * amp
        tot += amp; amp *= 0.5
    return out / tot

def moon(n=384):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    cx = cy = (n - 1) / 2; r = n / 2 - 2
    dx, dy = (x - cx) / r, (y - cy) / r
    d2 = dx * dx + dy * dy
    inside = d2 <= 1
    z = np.sqrt(np.clip(1 - d2, 0, 1))
    # yüzey: açık yaylalar + koyu "denizler" (maria) — düşük frekanslı gürültü eşiği
    low = fbm(n, 5, 2); fine = fbm(n, 6, 16); mid = fbm(n, 5, 6)
    maria = np.clip((0.53 - low) * 9.0, 0, 1)            # geniş, keskin sınırlı koyu denizler
    maria *= np.clip((1.05 - np.sqrt(d2)) * 3, 0, 1)
    albedo = 0.86 + 0.20 * (fine - 0.5) + 0.10 * (mid - 0.5) - 0.50 * maria
    height = 0.6 * (fine - 0.5)
    # kraterler: çoğu küçük (güç yasası), birkaç büyük ışınlı; kabartma hafif
    for i in range(90):
        cr = 0.010 + 0.05 * rng.random() ** 3.5 if i > 3 else rng.uniform(0.05, 0.08)
        a = rng.uniform(0, 2 * np.pi); rad = np.sqrt(rng.uniform(0, 0.85))
        px, py = rad * np.cos(a), rad * np.sin(a)
        dd = np.sqrt((dx - px) ** 2 + (dy - py) ** 2) / cr
        bowl = np.clip(1 - dd, 0, 1) ** 1.5
        rim = np.exp(-((dd - 1.0) ** 2) / 0.03)
        height += (-0.9 * bowl + 0.5 * rim) * cr * 9
        albedo += 0.035 * rim - 0.03 * bowl
        if i < 4:   # parlak ışın sistemi (Tycho/Kopernik benzeri)
            ang = np.arctan2(dy - py, dx - px)
            k = rng.integers(11, 19)
            rays = np.clip(np.sin(ang * k + rng.uniform(0, 6)) - 0.55, 0, 1) * 2.2
            albedo += 0.16 * rays * np.exp(-dd / 9.0) * (dd > 1.0) + 0.10 * np.exp(-dd / 1.6)
    # eğime göre gölgelendirme (sol üstten ışık) + küresel kararma
    gy, gx = np.gradient(height)
    shade = 1.0 + 1.6 * (-gx * 0.75 - gy * 0.65)
    limb = 0.55 + 0.45 * z ** 0.6
    v = np.clip(albedo * shade * limb, 0, 1)
    rgb = np.stack([v * 235 + 12, v * 233 + 12, v * 226 + 14], -1)
    edge = np.clip((1 - np.sqrt(d2)) * r / 1.5, 0, 1)      # yumuşak kenar
    alpha = (inside * edge * 255)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8), 'RGBA')
    img.filter(ImageFilter.GaussianBlur(0.6)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, 'moon.png'), optimize=True)

def cloud(name, seed, w=512, h=288):
    r = np.random.default_rng(seed)
    dens = np.zeros((h, w), np.float32)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    base_y = h * 0.66
    for _ in range(22):   # kümülüs: düz tabanın üstünde kabaran toplar
        cx = r.uniform(w * 0.14, w * 0.86)
        rad = r.uniform(h * 0.16, h * 0.34) * (1 - abs(cx / w - 0.5) * 0.9)
        cy = base_y - rad * r.uniform(0.35, 0.95)
        dens += np.clip(1 - ((x - cx) ** 2 + (y - cy) ** 2) / rad ** 2, 0, 1) ** 0.8
    n = np.asarray(Image.fromarray((fbm(512, 5, 6) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
    dens = np.clip(dens * (0.75 + 0.6 * n) - 0.25, 0, 1.6)
    dens *= np.clip((base_y + h * 0.10 - y) / (h * 0.10), 0, 1)       # düz taban
    a = np.clip(dens, 0, 1) ** 0.75
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), np.float32) / 255
    # ışık: üst parlak beyaz, alt mavi-gri gölge; yoğun yerler daha parlak
    t = np.clip((y - h * 0.18) / (h * 0.6), 0, 1)
    lum = 1.0 - 0.34 * t ** 1.4 - 0.10 * (1 - np.clip(dens, 0, 1))
    rgb = np.stack([lum * 250, lum * 252, np.clip(lum * 258, 0, 255)], -1)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), 'RGBA')
    img.resize((w // 2, h // 2), Image.LANCZOS).save(os.path.join(OUT, name), optimize=True)

def sun(n=384):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2; d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (n / 2)
    ang = np.arctan2(y - c, x - c)
    disk = np.clip((0.30 - d) / 0.012, 0, 1)
    corona = np.exp(-np.clip(d - 0.28, 0, None) * 5.5)
    rays = 0.5 + 0.5 * np.sin(ang * 12) * np.sin(ang * 5 + 1.3)
    glow = corona * (0.55 + 0.25 * rays) * np.clip(1 - d, 0, 1)
    a = np.clip(disk + glow * 0.85, 0, 1)
    core = np.clip(1 - d / 0.30, 0, 1)
    r_ = 255 * np.ones_like(d); g_ = 214 + 36 * core * disk; b_ = 96 + 120 * core * disk
    img = Image.fromarray(np.dstack([r_, np.clip(g_, 0, 255), np.clip(b_, 0, 255), a * 255]).astype(np.uint8), 'RGBA')
    img.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, 'sun.png'), optimize=True)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    moon(); cloud('cloud_a.png', 11); cloud('cloud_b.png', 29); sun()
    print('ok')
