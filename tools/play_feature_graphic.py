"""Google Play öne çıkan görsel (1024x500) — tamamen kodla çizilir (Faz 17.4).
Logo tools/brand_icon.py ile aynı geometriden; yazı tipi Inter (SIL OFL 1.1).
Çalıştır: python3 tools/play_feature_graphic.py → docs/play/feature_graphic_1024x500.png
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import brand_icon as bi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "play")
FONT_DIR = "/usr/share/fonts/opentype/inter"
W, H, SS = 1024, 500, 2


def font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONT_DIR, name), size * SS)
    except OSError:
        return ImageFont.load_default()


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.new("RGB", (W * SS, H * SS), (10, 11, 16))
    d = ImageDraw.Draw(img)
    # derin uzay degrade
    for y in range(H * SS):
        t = y / (H * SS)
        d.line([(0, y), (W * SS, y)], fill=(int(10 + 8 * t), int(11 + 6 * t), int(22 + 18 * (1 - t))))
    # yıldızlar (sabit tohum → her üretimde aynı)
    rnd = random.Random(21)
    for _ in range(140):
        x, y = rnd.random() * W * SS, rnd.random() * H * SS
        r = rnd.choice([1, 1, 2, 2, 3])
        a = rnd.randint(60, 200)
        d.ellipse([x, y, x + r, y + r], fill=(a, a, min(255, a + 30)))
    # limon parıltısı
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy, rr = 250 * SS, 250 * SS, 210 * SS
    gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(186, 250, 8, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(70 * SS))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    # logo karosu
    mark = bi.render(300 * SS, "legacy")
    img.alpha_composite(mark, (100 * SS, 100 * SS))
    d = ImageDraw.Draw(img)
    d.text((450 * SS, 150 * SS), "Juzzio", font=font("Inter-Black.otf", 92), fill=(245, 247, 250))
    d.text((452 * SS, 265 * SS), "Sınırsız sohbet, canlı çeviri", font=font("Inter-SemiBold.otf", 34), fill=(198, 241, 53))
    d.text((452 * SS, 315 * SS), "Uçtan uca şifreli mesajlar · sesli ve görüntülü arama", font=font("Inter-SemiBold.otf", 22),
           fill=(170, 178, 192))
    img.convert("RGB").resize((W, H), Image.LANCZOS).save(os.path.join(OUT, "feature_graphic_1024x500.png"), optimize=True)
    bi.render(512, "legacy").save(os.path.join(OUT, "icon_512.png"))
    print("Play görselleri üretildi:", OUT)


if __name__ == "__main__":
    main()
