#!/usr/bin/env python3
"""Juzzio uygulama tanıtım videosu (ilk giriş) — 720x1280, 30 fps, 20 sn.

Kullanım:
  python3 tools/intro_video/intro.py tr            # Türkçe sürüm
  python3 tools/intro_video/intro.py en            # İngilizce sürüm
  python3 tools/intro_video/intro.py stills tr     # kontrol için ara kareler (JPEG)
Müzik: --music <mp3> (ilk 20 sn, başta 0.3 sn yükselme, sonda 1.6 sn sönme).
Tüm kareler kodla çizilir (PIL); görsel olarak yalnız uygulama logosu kullanılır.
"""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS, T_TOTAL = 720, 1280, 30, 20.0
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FD = '/usr/share/fonts/opentype/inter/'
def F(name, size): return ImageFont.truetype(FD + name, size)

DEEP = (10, 8, 28); INK = (16, 12, 40); VIOLET = (123, 92, 255); LIME = (212, 255, 79)
PINK = (255, 92, 168); SKY = (90, 180, 255); WHITE = (255, 255, 255); MUTED = (200, 194, 236)
LOGO = Image.open(os.path.join(ROOT, 'assets/logo/juzzio_logo.png')).convert('RGBA')

TEXT = {
    'tr': dict(
        tag='Dünyayla kendi dilinde konuş',
        s2='Anında çeviri', s2b='Her mesaj senin dilinde',
        b_in='Hello! How are you? 👋', b_out='Merhaba! Nasılsın?', b_me='Harikayım, sen nasılsın?',
        s3='Uçtan uca şifreli', s3b='Mesajların yalnız sende ve karşındakinde',
        s4='Hikâyeler ve aramalar', s4b='Sesli · Görüntülü · Grup',
        s5='Sana göre değişen tema', s5b='Saate ve havaya göre canlanır',
        s6='Juzzio Topluluğu', s6b='Tüm güncellemeler tek kanalda',
        end='Hadi başlayalım', endb='Juzzio’ya hoş geldin',
    ),
    'en': dict(
        tag='Talk to the world in your language',
        s2='Instant translation', s2b='Every message in your language',
        b_in='Merhaba! Nasılsın? 👋', b_out='Hello! How are you?', b_me='Great, and you?',
        s3='End-to-end encrypted', s3b='Only you and your chat can read it',
        s4='Stories & calls', s4b='Voice · Video · Group',
        s5='A theme that follows you', s5b='Comes alive with time and weather',
        s6='Juzzio Community', s6b='Every update in one channel',
        end="Let's get started", endb='Welcome to Juzzio',
    ),
}

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def seg(t, a, b): return clamp((t - a) / (b - a))
def ease_out(t): t = clamp(t); return 1 - (1 - t) ** 3
def ease_io(t): t = clamp(t); return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2
def back(t, s=1.6): t = clamp(t) - 1; return t * t * ((s + 1) * t + s) + 1
def lerp(a, b, t): return a + (b - a) * t
def mix(c1, c2, t): return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))

def strip_emoji(s): return ''.join(ch for ch in s if ord(ch) < 0x2000 or ch in 'âîûÂÎÛ’').strip()

# ---------------------------------------------------------------- çizim yardımcıları
def layer(): return Image.new('RGBA', (W, H), (0, 0, 0, 0))

def text_center(img, s, f, y, fill, a=1.0, dx=0):
    if a <= 0: return
    L = layer(); d = ImageDraw.Draw(L)
    w = d.textlength(s, font=f)
    d.text(((W - w) / 2 + dx, y), s, font=f, fill=fill + (int(255 * clamp(a)),))
    img.alpha_composite(L)

def glow(img, cx, cy, r, col, a):
    if a <= 0: return
    small = Image.new('RGBA', (W // 4, H // 4), (0, 0, 0, 0))
    ImageDraw.Draw(small).ellipse([(cx - r) / 4, (cy - r) / 4, (cx + r) / 4, (cy + r) / 4], fill=col + (int(255 * clamp(a)),))
    img.alpha_composite(small.filter(ImageFilter.GaussianBlur(14)).resize((W, H), Image.BILINEAR))

_BLOBS = [(140, 260, 260, VIOLET, 120, 0.6), (600, 420, 230, PINK, 80, 0.45), (360, 1040, 300, (60, 90, 255), 95, 0.35),
          (620, 980, 180, LIME, 40, 0.7)]
def aurora(t, tint=None):
    base = Image.new('RGBA', (W, H), DEEP + (255,))
    small = Image.new('RGBA', (W // 4, H // 4), (0, 0, 0, 0)); d = ImageDraw.Draw(small)
    for (cx, cy, r, col, a, sp) in _BLOBS:
        c = col if tint is None else mix(col, tint, 0.5)
        x = cx + 46 * math.sin(t * sp); y = cy + 60 * math.cos(t * sp * 0.8)
        d.ellipse([(x - r) / 4, (y - r) / 4, (x + r) / 4, (y + r) / 4], fill=c + (a,))
    base.alpha_composite(small.filter(ImageFilter.GaussianBlur(20)).resize((W, H), Image.BILINEAR))
    return base

def rrect(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

def logo_at(img, cx, cy, size, a=1.0):
    if size < 2 or a <= 0: return
    lg = LOGO.resize((int(size), int(size)), Image.LANCZOS)
    if a < 1:
        al = lg.getchannel('A').point(lambda v: int(v * a)); lg.putalpha(al)
    img.alpha_composite(lg, (int(cx - size / 2), int(cy - size / 2)))

def phone(img, cx, cy, s=1.0, a=1.0, screen=(18, 15, 44)):
    """Telefon çerçevesi; ekran kutusunu döndürür."""
    w, h = 430 * s, 800 * s
    L = layer(); d = ImageDraw.Draw(L)
    x0, y0 = cx - w / 2, cy - h / 2
    rrect(d, [x0 + 8, y0 + 18, x0 + w + 8, y0 + h + 18], 58 * s, fill=(0, 0, 0, int(110 * a)))
    L = L.filter(ImageFilter.GaussianBlur(18)); d = ImageDraw.Draw(L)
    rrect(d, [x0, y0, x0 + w, y0 + h], 58 * s, fill=(36, 32, 70, int(255 * a)))
    rrect(d, [x0 + 12 * s, y0 + 12 * s, x0 + w - 12 * s, y0 + h - 12 * s], 48 * s, fill=screen + (int(255 * a),))
    rrect(d, [cx - 58 * s, y0 + 26 * s, cx + 58 * s, y0 + 58 * s], 16 * s, fill=(0, 0, 0, int(255 * a)))
    img.alpha_composite(L)
    return (x0 + 12 * s, y0 + 12 * s, x0 + w - 12 * s, y0 + h - 12 * s)

def bubble(img, x, y, text, f, me, a=1.0, maxw=300, col=None):
    if a <= 0: return 0
    L = layer(); d = ImageDraw.Draw(L)
    tw = d.textlength(text, font=f); bw = min(maxw, tw + 40); bh = 58
    bx = x - bw if me else x
    c = col or ((123, 92, 255) if me else (44, 40, 86))
    rrect(d, [bx, y, bx + bw, y + bh], 24, fill=c + (int(255 * a),))
    d.text((bx + 20, y + 15), text, font=f, fill=WHITE + (int(255 * a),))
    img.alpha_composite(L)
    return bh

# ---------------------------------------------------------------- vektör simgeler
def sun(d, cx, cy, r, a, col=(255, 194, 61)):
    for j in range(8):
        ang = j * math.pi / 4
        d.line([(cx + math.cos(ang) * r * 1.3, cy + math.sin(ang) * r * 1.3), (cx + math.cos(ang) * r * 1.75, cy + math.sin(ang) * r * 1.75)],
               fill=col + (int(255 * a),), width=max(2, int(r * 0.22)))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (int(255 * a),))

def moon(img, cx, cy, r, a):
    L = Image.new('L', (W, H), 0); d = ImageDraw.Draw(L)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=int(255 * a))
    d.ellipse([cx - r * 0.5, cy - r * 1.2, cx + r * 1.4, cy + r * 0.6], fill=0)
    col = Image.new('RGBA', (W, H), (255, 224, 138, 255)); col.putalpha(L)
    img.alpha_composite(col)

def cloud(d, cx, cy, r, a, col=(235, 240, 255)):
    c = col + (int(255 * a),)
    d.ellipse([cx - r * 1.1, cy - r * 0.2, cx - r * 0.1, cy + r * 0.8], fill=c)
    d.ellipse([cx - r * 0.6, cy - r * 0.8, cx + r * 0.6, cy + r * 0.5], fill=c)
    d.ellipse([cx + 0.1 * r, cy - r * 0.3, cx + r * 1.1, cy + r * 0.7], fill=c)
    d.rounded_rectangle([cx - r * 1.1, cy + r * 0.1, cx + r * 1.1, cy + r * 0.8], radius=r * 0.35, fill=c)

def star(d, cx, cy, r, a, col=WHITE):
    pts = []
    for j in range(8):
        ang = j * math.pi / 4 - math.pi / 2
        rr = r if j % 2 == 0 else r * 0.32
        pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
    d.polygon(pts, fill=col + (int(255 * a),))

def padlock(img, cx, cy, s, a, closed):
    L = layer(); d = ImageDraw.Draw(L)
    al = int(255 * a)
    lift = 0 if closed else 34 * s
    d.arc([cx - 46 * s, cy - 118 * s - lift, cx + 46 * s, cy - 20 * s - lift], 180, 360, fill=(220, 214, 255, al), width=int(16 * s))
    d.line([(cx - 46 * s + 8 * s, cy - 69 * s - lift), (cx - 46 * s + 8 * s, cy - 30 * s)], fill=(220, 214, 255, al), width=int(16 * s))
    d.line([(cx + 46 * s - 8 * s, cy - 69 * s - lift), (cx + 46 * s - 8 * s, cy - 30 * s - (lift if not closed else 0))], fill=(220, 214, 255, al), width=int(16 * s))
    rrect(d, [cx - 78 * s, cy - 40 * s, cx + 78 * s, cy + 82 * s], 26 * s, fill=LIME + (al,))
    d.ellipse([cx - 14 * s, cy + 2 * s, cx + 14 * s, cy + 30 * s], fill=INK + (al,))
    d.rectangle([cx - 5 * s, cy + 20 * s, cx + 5 * s, cy + 50 * s], fill=INK + (al,))
    img.alpha_composite(L)

# ---------------------------------------------------------------- sahneler (t: sahne içi sn)
def s_logo(t, T, X):
    img = aurora(t)
    p = back(seg(t, 0.1, 0.9), 1.4)
    glow(img, W / 2, 520, 220 * p + 1, LIME, 0.32 * clamp(p))
    logo_at(img, W / 2, 520, 240 * p)
    a = ease_out(seg(t, 0.7, 1.3))
    text_center(img, 'Juzzio', F('InterDisplay-Bold.otf', 96), 690 + 24 * (1 - a), WHITE, a)
    a2 = ease_out(seg(t, 1.1, 1.7))
    text_center(img, X['tag'], F('Inter-Medium.otf', 32), 812 + 18 * (1 - a2), MUTED, a2)
    return img

def s_translate(t, T, X):
    img = aurora(t + 3)
    a = ease_out(seg(t, 0, 0.5))
    text_center(img, X['s2'], F('InterDisplay-Bold.otf', 58), 110 + 20 * (1 - a), WHITE, a)
    text_center(img, X['s2b'], F('Inter-Medium.otf', 28), 190, MUTED, a)
    sc = phone(img, W / 2, 760 + 60 * (1 - ease_out(seg(t, 0, 0.6))), 1.0, a)
    f = F('Inter-SemiBold.otf', 24)
    x0, y0, x1, _ = sc
    # sohbet başlığı: kişi + çevrimiçi + kilit
    if a > 0:
        Hh = layer(); hd = ImageDraw.Draw(Hh); al = int(255 * a)
        hd.ellipse([x0 + 24, y0 + 56, x0 + 72, y0 + 104], fill=(255, 140, 190, al))
        hd.ellipse([x0 + 38, y0 + 64, x0 + 58, y0 + 84], fill=(255, 230, 240, al))
        hd.pieslice([x0 + 30, y0 + 84, x0 + 66, y0 + 112], 180, 360, fill=(255, 230, 240, al))
        hd.text((x0 + 86, y0 + 58), 'Ayşe' if X is TEXT['tr'] else 'Emma', font=F('Inter-Bold.otf', 22), fill=WHITE + (al,))
        hd.text((x0 + 86, y0 + 84), 'çevrimiçi' if X is TEXT['tr'] else 'online', font=F('Inter-Medium.otf', 16), fill=(120, 230, 160, al))
        hd.line([(x0 + 20, y0 + 118), (x1 - 20, y0 + 118)], fill=(255, 255, 255, int(30 * a)), width=1)
        img.alpha_composite(Hh)
        y0 += 20
    # gelen mesaj → çeviri (kart çevrilir gibi daralıp genişler)
    p_in = ease_out(seg(t, 0.5, 0.9))
    flip = seg(t, 1.4, 1.9)
    sq = abs(math.cos(flip * math.pi))
    txt = strip_emoji(X['b_in']) if flip < 0.5 else X['b_out']
    if p_in > 0:
        L = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        bubble(L, x0 + 26, y0 + 120, txt, f, False, p_in, col=(44, 40, 86) if flip < 0.5 else (34, 92, 84))
        if sq < 0.999:
            bb = L.getbbox()
            if bb:
                crop = L.crop(bb); nh = max(1, int(crop.height * max(sq, 0.04)))
                crop = crop.resize((crop.width, nh), Image.BILINEAR)
                L = Image.new('RGBA', (W, H), (0, 0, 0, 0)); L.alpha_composite(crop, (bb[0], int(bb[1] + (bb[3] - bb[1] - nh) / 2)))
        img.alpha_composite(L)
    if flip >= 1:
        d = ImageDraw.Draw(img)
        d.text((x0 + 30, y0 + 186), '✓ ' + ('Çevrildi' if X is TEXT['tr'] else 'Translated'), font=F('Inter-Medium.otf', 18), fill=LIME + (int(255 * seg(t, 1.9, 2.2)),))
    p_me = ease_out(seg(t, 2.2, 2.6))
    bubble(img, x1 - 26, y0 + 240 - 20 * (1 - p_me), X['b_me'], f, True, p_me)
    return img

def s_secure(t, T, X):
    img = aurora(t + 7, tint=(40, 200, 140))
    a = ease_out(seg(t, 0, 0.5))
    text_center(img, X['s3'], F('InterDisplay-Bold.otf', 58), 110 + 20 * (1 - a), WHITE, a)
    text_center(img, X['s3b'], F('Inter-Medium.otf', 28), 190, MUTED, a)
    closed = t > 1.2
    p = back(seg(t, 0.2, 0.8), 1.3)
    glow(img, W / 2, 660, 200, LIME, 0.25 * seg(t, 1.2, 1.6))
    padlock(img, W / 2, 680, 1.25 * max(p, 0.01), clamp(p), closed)
    # şifreli karakter akışı (mesaj → anlamsız karakterler)
    d = ImageDraw.Draw(img)
    fm = F('Inter-Medium.otf', 22)
    for i in range(8):
        y = 900 + i * 34
        ph = (t * 1.3 + i * 0.13) % 1.0
        s = ''.join('01#%&*@$'[(i * 7 + k + int(t * 12)) % 8] for k in range(18))
        d.text((W / 2 - 150 + 40 * math.sin(i), y), s, font=fm, fill=(140, 255, 200, int(110 * clamp(a) * (1 - ph))))
    return img

def s_stories(t, T, X):
    img = aurora(t + 11, tint=PINK)
    a = ease_out(seg(t, 0, 0.5))
    text_center(img, X['s4'], F('InterDisplay-Bold.otf', 58), 110 + 20 * (1 - a), WHITE, a)
    text_center(img, X['s4b'], F('Inter-Medium.otf', 28), 190, MUTED, a)
    L = layer(); d = ImageDraw.Draw(L)
    cols = [(PINK, (255, 196, 61)), (VIOLET, SKY), (LIME, (60, 220, 160)), ((255, 140, 60), PINK)]
    for i in range(4):
        p = back(seg(t, 0.25 + i * 0.12, 0.75 + i * 0.12), 1.5)
        if p <= 0: continue
        cx = 135 + i * 150; cy = 440; r = 56 * p
        rot = t * 2 + i
        for k in range(36):  # dönen degrade halka
            ang0 = rot + k * math.pi / 18
            c = mix(cols[i][0], cols[i][1], (math.sin(ang0) + 1) / 2)
            d.arc([cx - r - 9, cy - r - 9, cx + r + 9, cy + r + 9], math.degrees(ang0), math.degrees(ang0) + 11, fill=c + (255,), width=7)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(46, 40, 92, 255))
        d.ellipse([cx - r * 0.42, cy - r * 0.62, cx + r * 0.42, cy + r * 0.2], fill=(210, 200, 255, 255))
        d.pieslice([cx - r * 0.75, cy + r * 0.1, cx + r * 0.75, cy + r * 1.3], 180, 360, fill=(210, 200, 255, 255))
    img.alpha_composite(L)
    # arama düğmeleri (nabız)
    for i, (col, kind) in enumerate([((60, 210, 120), 'voice'), (VIOLET, 'video')]):
        p = back(seg(t, 1.2 + i * 0.15, 1.6 + i * 0.15), 1.6)
        if p <= 0: continue
        cx = W / 2 + (i * 2 - 1) * 110; cy = 780
        pulse = (t * 1.2 + i * 0.5) % 1.0
        G = layer(); g = ImageDraw.Draw(G)
        rr = 70 + 50 * pulse
        g.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=col + (int(160 * (1 - pulse)),), width=4)
        g.ellipse([cx - 70 * p, cy - 70 * p, cx + 70 * p, cy + 70 * p], fill=col + (255,))
        if kind == 'voice':  # ahize
            g.arc([cx - 30, cy - 30, cx + 30, cy + 30], 110, 250, fill=WHITE + (255,), width=14)
        else:  # kamera
            g.rounded_rectangle([cx - 30, cy - 18, cx + 12, cy + 18], 6, fill=WHITE + (255,))
            g.polygon([(cx + 14, cy), (cx + 34, cy - 16), (cx + 34, cy + 16)], fill=WHITE + (255,))
        img.alpha_composite(G)
    return img

def s_theme(t, T, X):
    k = ease_io(seg(t, 0.4, 2.4))  # gündüz → gece
    top = mix((96, 170, 255), (14, 12, 48), k); bot = mix((255, 196, 140), (40, 26, 90), k)
    g = Image.new('RGB', (1, 256))
    for i in range(256): g.putpixel((0, i), mix(top, bot, i / 255))
    img = g.resize((W, H)).convert('RGBA')
    L = layer(); d = ImageDraw.Draw(L)
    for i in range(14):  # minik süzülen simgeler (uygulamadaki hava teması)
        sx = (i * 97 + t * 30 * (1 + i % 3)) % (W + 80) - 40
        sy = 300 + (i * 131) % 820 + 8 * math.sin(t * 2 + i)
        if i % 3 == 0: cloud(d, sx, sy, 16 + (i % 4) * 3, 0.55)
        elif k < 0.5: sun(d, sx, sy, 8 + (i % 3) * 2, 0.6 * (1 - k * 2))
        else: star(d, sx, sy, 9 + (i % 3) * 2, 0.7 * (k * 2 - 1))
    img.alpha_composite(L)
    # büyük güneş batar, ay doğar (ayrı katmanda → saydamlık doğru karışır)
    S = layer(); sun(ImageDraw.Draw(S), W * 0.72, 470 + 360 * k, 46, 1 - k); img.alpha_composite(S)
    if k > 0.3: moon(img, W * 0.3, 560 - 160 * (k - 0.3), 52, clamp((k - 0.3) / 0.5))
    a = ease_out(seg(t, 0, 0.5))
    text_center(img, X['s5'], F('InterDisplay-Bold.otf', 54), 110 + 20 * (1 - a), WHITE, a)
    text_center(img, X['s5b'], F('Inter-Medium.otf', 28), 190, (240, 238, 255), a)
    return img

def s_community(t, T, X):
    img = aurora(t + 17)
    a = ease_out(seg(t, 0, 0.5))
    p = back(seg(t, 0.15, 0.75), 1.4)
    glow(img, W / 2, 540, 210, VIOLET, 0.4 * clamp(p))
    logo_at(img, W / 2, 540, 210 * p)
    # onay rozeti
    if p > 0.6:
        L = layer(); d = ImageDraw.Draw(L)
        bx, by, br = W / 2 + 80, 470, 30 * clamp((p - 0.6) / 0.4)
        d.ellipse([bx - br, by - br, bx + br, by + br], fill=(40, 150, 255, 255))
        d.line([(bx - br * 0.45, by), (bx - br * 0.1, by + br * 0.35), (bx + br * 0.5, by - br * 0.35)], fill=WHITE + (255,), width=max(2, int(br * 0.22)))
        img.alpha_composite(L)
    text_center(img, X['s6'], F('InterDisplay-Bold.otf', 62), 720 + 20 * (1 - a), WHITE, a)
    text_center(img, X['s6b'], F('Inter-Medium.otf', 28), 806, MUTED, a)
    # duyuru kartı kayar
    q = ease_out(seg(t, 0.8, 1.3))
    if q > 0:
        L = layer(); d = ImageDraw.Draw(L)
        y = 900 + 40 * (1 - q)
        rrect(d, [110, y, W - 110, y + 110], 28, fill=(40, 34, 84, int(235 * q)))
        d.text((140, y + 22), 'Juzzio Official', font=F('Inter-Bold.otf', 22), fill=WHITE + (int(255 * q),))
        d.text((140, y + 58), 'v1.2.7  ·  ' + ('Yeni güncelleme yayında' if X is TEXT['tr'] else 'New update is live'),
               font=F('Inter-Medium.otf', 20), fill=MUTED + (int(255 * q),))
        img.alpha_composite(L)
    return img

def s_end(t, T, X):
    img = aurora(t + 21)
    p = back(seg(t, 0.0, 0.7), 1.3)
    glow(img, W / 2, 520, 230, LIME, 0.3 * clamp(p))
    logo_at(img, W / 2, 520, 220 * p)
    a = ease_out(seg(t, 0.3, 0.9))
    text_center(img, X['end'], F('InterDisplay-Bold.otf', 66), 700 + 20 * (1 - a), WHITE, a)
    text_center(img, X['endb'], F('Inter-Medium.otf', 30), 790, LIME, ease_out(seg(t, 0.6, 1.1)))
    fade = seg(t, T - 0.5, T)
    if fade > 0: img.alpha_composite(Image.new('RGBA', (W, H), (0, 0, 0, int(255 * fade))))
    return img

SCENES = [(s_logo, 2.6), (s_translate, 3.4), (s_secure, 3.0), (s_stories, 3.0), (s_theme, 3.0), (s_community, 2.6), (s_end, 2.4)]
assert abs(sum(T for _, T in SCENES) - T_TOTAL) < 1e-6

def frame_at(gt, X):
    """Genel zamandan kare; sahne geçişlerinde 0.25 sn çapraz geçiş."""
    acc = 0.0
    for i, (fn, T) in enumerate(SCENES):
        if gt < acc + T or i == len(SCENES) - 1:
            t = gt - acc
            img = fn(t, T, X)
            if i + 1 < len(SCENES) and t > T - 0.25:
                nxt = SCENES[i + 1][0](0.0, SCENES[i + 1][1], X)
                k = (t - (T - 0.25)) / 0.25
                img = Image.blend(img, nxt, ease_io(k))
            return img
        acc += T

def render(lang, music, out):
    X = TEXT[lang]
    tmp = out + '.video.mp4'
    p = subprocess.Popen(['ffmpeg', '-y', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', tmp],
                         stdin=subprocess.PIPE)
    for i in range(int(T_TOTAL * FPS)):
        p.stdin.write(frame_at(i / FPS, X).convert('RGB').tobytes())
    p.stdin.close()
    if p.wait() != 0: sys.exit('video kodlanamadı')
    af = f'afade=t=in:st=0:d=0.3,afade=t=out:st={T_TOTAL - 1.6}:d=1.6'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', tmp, '-i', music, '-t', str(T_TOTAL), '-map', '0:v', '-map', '1:a',
                    '-c:v', 'copy', '-af', af, '-c:a', 'aac', '-b:a', '96k', '-ac', '2', '-shortest', '-movflags', '+faststart', out], check=True)
    os.remove(tmp)

if __name__ == '__main__':
    args = sys.argv[1:]
    music = None
    if '--music' in args:
        i = args.index('--music'); music = args[i + 1]; del args[i:i + 2]
    if args and args[0] == 'stills':
        lang = args[1] if len(args) > 1 else 'tr'
        os.makedirs('/tmp/claude-0/intro', exist_ok=True)
        for s in (1.5, 4.5, 6.4, 8.6, 10.6, 13.0, 14.8, 16.2, 18.8):
            frame_at(s, TEXT[lang]).convert('RGB').save(f'/tmp/claude-0/intro/still_{lang}_{s:04.1f}.jpg', quality=85)
    else:
        lang = args[0] if args else 'tr'
        if not music: sys.exit('--music <mp3> gerekli')
        render(lang, music, os.path.join(ROOT, f'assets/intro/juzzio_intro_{lang}.mp4'))
