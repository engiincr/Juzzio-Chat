"""Juzzio 2.1 — resmî logodan (assets/brand/juzzio_logo_source.png, siyah zemin + limon "J")
tüm platform ikonlarını ve uygulama içi logo dosyalarını üretir.
Çalıştır: python3 tools/brand_logo.py
Üretilenler:
  assets/brand/juzzio_glyph.png          — saydam zeminde limon J (uygulama içi logo)
  assets/brand/juzzio_mark_512.png        — ikon görünümü (yuvarlak kare)
  assets/logo/juzzio_logo.png             — açılış ekranı / topluluk avatarı (siyah kare, 1024)
  assets/images/pdf_logo.png              — PDF anteti (beyaz kâğıt için J + "Juzzio")
  android mipmap (eski + uyarlanabilir + tematik), açılış logosu, Android 12+ açılış ikonu,
  bildirim küçük ikonu (beyaz siluet), iOS / macOS AppIcon, Windows .ico, docs/logo.png
"""
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "brand", "juzzio_logo_source.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
BG = (0, 0, 0)


def glyph_mask(src):
    """Limon J'nin yumuşak kenarlı maskesi (yeşil kanaldan)"""
    g = src.convert("RGB").split()[1]
    return g.point(lambda v: 0 if v < 24 else (255 if v > 232 else int((v - 24) * 255 / 208)))


def lime_color(src, mask):
    px = src.convert("RGB").load()
    m = mask.load()
    w, h = src.size
    acc = [0, 0, 0]
    n = 0
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            if m[x, y] == 255:
                r, gg, b = px[x, y]
                acc[0] += r
                acc[1] += gg
                acc[2] += b
                n += 1
    return tuple(int(c / max(1, n)) for c in acc)


def glyph(src, color=None):
    mask = glyph_mask(src)
    col = color or lime_color(src, mask)
    out = Image.new("RGBA", src.size, col + (0,))
    out.putalpha(mask)
    bbox = mask.getbbox()
    return out.crop(bbox), col


def place(g, size, frac, bg=None, radius=0.0):
    """g'yi size×size tuvalin ortasına, uzun kenarı size*frac olacak şekilde koyar"""
    canvas = Image.new("RGBA", (size, size), (bg + (255,)) if bg else (0, 0, 0, 0))
    gw, gh = g.size
    k = size * frac / max(gw, gh)
    gr = g.resize((max(1, int(gw * k)), max(1, int(gh * k))), Image.LANCZOS)
    canvas.alpha_composite(gr, ((size - gr.size[0]) // 2, (size - gr.size[1]) // 2))
    if radius > 0:
        m = Image.new("L", (size * 4, size * 4), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius), fill=255)
        m = m.resize((size, size), Image.LANCZOS)
        canvas.putalpha(ImageChops.multiply(canvas.split()[3], m))
    return canvas


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


def main():
    src = Image.open(SRC)
    g, lime = glyph(src)
    white, _ = glyph(src, (255, 255, 255))
    # Uygulama içi
    save(place(g, 1024, 0.98), "assets", "brand", "juzzio_glyph.png")
    save(place(g, 512, 0.62, BG, 0.24), "assets", "brand", "juzzio_mark_512.png")
    save(place(g, 1024, 0.66, BG).convert("RGB"), "assets", "logo", "juzzio_logo.png")
    save(place(g, 512, 0.62, BG, 0.24), "docs", "logo.png")
    # Android başlatıcı
    for dpi, s in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        a = int(s * 108 / 48)
        save(place(g, s, 0.6, BG, 0.22), "android", "app", "src", "main", "res", f"mipmap-{dpi}", "ic_launcher.png")
        save(Image.new("RGB", (a, a), BG), "android", "app", "src", "main", "res", f"mipmap-{dpi}", "ic_launcher_background.png")
        # 108dp tuvalde 66dp güvenli alan → glif ~%42
        save(place(g, a, 0.42), "android", "app", "src", "main", "res", f"mipmap-{dpi}", "ic_launcher_foreground.png")
        save(place(white, a, 0.42), "android", "app", "src", "main", "res", f"mipmap-{dpi}", "ic_launcher_monochrome.png")
    # Açılış logosu (eski Android) ve Android 12+ açılış ikonu
    for dpi, s in {"mdpi": 120, "hdpi": 180, "xhdpi": 240, "xxhdpi": 360, "xxxhdpi": 480}.items():
        save(place(g, s, 0.7), "android", "app", "src", "main", "res", f"drawable-{dpi}", "juzzio_launch_logo.png")
    save(place(g, 864, 0.42), "android", "app", "src", "main", "res", "drawable-xxhdpi", "juzzio_splash_icon.png")
    # Bildirim küçük ikonu: beyaz siluet (24dp)
    for dpi, s in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
        save(place(white, s, 0.86), "android", "app", "src", "main", "res", f"drawable-{dpi}", "ic_stat_juzzio.png")
    # iOS (saydamlık yok, köşeleri sistem yuvarlar)
    ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for it in json.load(open(os.path.join(ios, "Contents.json")))["images"]:
        fn = it.get("filename")
        if not fn:
            continue
        base = float(it["size"].split("x")[0])
        sc = float(it["scale"].rstrip("x"))
        px = int(round(base * sc))
        place(g, px, 0.6, BG).convert("RGB").save(os.path.join(ios, fn), optimize=True)
    # macOS (yuvarlak kare, kenar boşluklu)
    mac = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for px in (16, 32, 64, 128, 256, 512, 1024):
        inner = place(g, int(px * 0.82), 0.6, BG, 0.22)
        c = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        c.alpha_composite(inner, ((px - inner.size[0]) // 2, (px - inner.size[1]) // 2))
        c.save(os.path.join(mac, f"app_icon_{px}.png"), optimize=True)
    # Windows
    ico = place(g, 256, 0.62, BG, 0.22)
    ico.save(os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico"),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # PDF anteti: beyaz kâğıtta okunur (koyu "Juzzio" yazısı + limon J, siyah konturlu kare)
    pdf = Image.new("RGBA", (1200, 488), (0, 0, 0, 0))
    tile = place(g, 420, 0.62, BG, 0.22)
    pdf.alpha_composite(tile, (20, 34))
    try:
        font = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Black.otf", 190)
    except OSError:
        font = ImageFont.load_default()
    ImageDraw.Draw(pdf).text((480, 118), "Juzzio", font=font, fill=(14, 15, 18, 255))
    save(pdf, "assets", "images", "pdf_logo.png")
    print("logo dosyaları üretildi · limon:", "#%02X%02X%02X" % lime)


if __name__ == "__main__":
    main()
