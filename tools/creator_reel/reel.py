#!/usr/bin/env python3
"""Juzzio yapımcı tanıtım videosu (Engin ÇIRPAN) — 720x1280, 30 fps."""
import math, subprocess, sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, FPS = 720, 1280, 30
OUT = '/tmp/claude-0/reel/out'
os.makedirs(OUT, exist_ok=True)
FD = '/usr/share/fonts/opentype/inter/'
def F(name, size): return ImageFont.truetype(FD + name, size)
MONO = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
def M(size): return ImageFont.truetype(MONO, size)

INK = (14, 10, 34); BONE = (238, 236, 245); VIOLET = (123, 92, 255); LIME = (212, 255, 79)
INDIGO = (30, 20, 78); DEEP = (12, 9, 30); WHITE = (255, 255, 255)
PHOTO = Image.open('/home/claude/juzzio/assets/creator/engin.jpg').convert('RGB')
LOGO = Image.open('/home/claude/juzzio/assets/logo/juzzio_logo.png').convert('RGBA')

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease_out(t): t = clamp(t); return 1 - (1 - t) ** 3
def ease_in_out(t): t = clamp(t); return 4*t*t*t if t < 0.5 else 1 - (-2*t + 2) ** 3 / 2
def back(t, s=1.70158): t = clamp(t); t -= 1; return t*t*((s+1)*t + s) + 1
def seg(t, a, b): return clamp((t - a) / (b - a))
def lerp(a, b, t): return a + (b - a) * t
def mix(c1, c2, t): return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))

def text_w(d, s, f): return d.textlength(s, font=f)

def center_text(img, s, f, y, fill, alpha=1.0, dx=0):
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    w = text_w(d, s, f); d.text(((W - w) / 2 + dx, y), s, font=f, fill=fill + (int(255 * clamp(alpha)),))
    img.alpha_composite(layer)
    return w

def put_text(img, xy, s, f, fill, alpha=1.0, anchor='la'):
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.text(xy, s, font=f, fill=fill + (int(255 * clamp(alpha)),), anchor=anchor)
    img.alpha_composite(layer)

def gradient_bg(c1, c2, angle_shift=0.0):
    g = Image.new('RGB', (1, 256))
    for i in range(256): g.putpixel((0, i), mix(c1, c2, i / 255))
    return g.resize((W, H)).convert('RGBA')

def aurora(base, blobs, t):
    img = base.copy()
    layer = Image.new('RGBA', (W // 4, H // 4), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    for (cx, cy, r, col, a, sp) in blobs:
        x = cx + 30 * math.sin(t * sp); y = cy + 40 * math.cos(t * sp * 0.8)
        d.ellipse([(x - r) / 4, (y - r) / 4, (x + r) / 4, (y + r) / 4], fill=col + (a,))
    layer = layer.filter(ImageFilter.GaussianBlur(22)).resize((W, H), Image.BILINEAR)
    img.alpha_composite(layer)
    return img

def guides(img, alpha, col=(120, 100, 200), dash=False):
    d = ImageDraw.Draw(img)
    a = int(110 * clamp(alpha))
    for x in (120, W - 120):
        d.line([(x, 0), (x, H)], fill=col + (a,), width=1)
    for y in (500, 690):
        d.line([(0, y), (W, y)], fill=col + (a,), width=1)

def glass(img, box, radius=36, tint=(255, 255, 255), a=46, border=90, blur=18):
    x0, y0, x1, y1 = [int(v) for v in box]
    region = img.crop((x0, y0, x1, y1)).filter(ImageFilter.GaussianBlur(blur))
    mask = Image.new('L', region.size, 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, region.size[0]-1, region.size[1]-1], radius, fill=255)
    img.paste(region, (x0, y0), mask)
    over = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(over)
    d.rounded_rectangle([x0, y0, x1, y1], radius, fill=tint + (a,), outline=(255, 255, 255, border), width=2)
    img.alpha_composite(over)

def rounded_photo(img, box, radius, zoom=1.0, focus=(0.55, 0.3)):
    x0, y0, x1, y1 = [int(v) for v in box]; w, h = x1 - x0, y1 - y0
    if w <= 2 or h <= 2: return
    pw, ph = PHOTO.size
    scale = max(w / pw, h / ph) * zoom
    rw, rh = int(pw * scale), int(ph * scale)
    ph_img = PHOTO.resize((rw, rh), Image.LANCZOS)
    cx = int(clamp(focus[0] * rw - w / 2, 0, rw - w)); cy = int(clamp(focus[1] * rh - h / 2, 0, rh - h))
    crop = ph_img.crop((cx, cy, cx + w, cy + h)).convert('RGBA')
    mask = Image.new('L', (w, h), 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=255)
    img.paste(crop, (x0, y0), mask)

# ---------------------------------------------------------------------------- sahneler
def s_hello(t, T):
    img = Image.new('RGBA', (W, H), BONE + (255,))
    guides(img, ease_out(seg(t, 0, 0.6)))
    d = ImageDraw.Draw(img)
    f = F('InterDisplay-Bold.otf', 168)
    word = 'Hello'
    n = int(clamp((t - 0.35) / 1.25) * len(word) + 0.0001)
    shown = word[:n]
    full_w = text_w(d, word, f)
    x = (W - full_w) / 2; y = 505
    d.text((x, y), shown, font=f, fill=INK)
    cw = text_w(d, shown, f)
    if (int(t * 2.4) % 2 == 0) or n < len(word):
        d.rectangle([x + cw + 6, y + 30, x + cw + 20, y + 190], fill=LIME)
        d.rectangle([x + cw + 6, y + 30, x + cw + 9, y + 190], fill=INK)
    # ölçü etiketleri
    a = ease_out(seg(t, 0.4, 1.0))
    put_text(img, (124, 476), f'{int(full_w)} px', M(14), (90, 70, 170), a)
    put_text(img, (W - 124, 700), 'x 1.000', M(14), (90, 70, 170), a, anchor='ra')
    for (px, py) in ((120, 500), (W - 120, 500), (120, 690), (W - 120, 690)):
        d.ellipse([px - 5, py - 5, px + 5, py + 5], outline=VIOLET, width=2)
    put_text(img, (W / 2, 1180), 'JUZZIO · CREATOR REEL', M(16), (110, 95, 170), a, anchor='ma')
    # çıkışta hafif yakınlaşma
    z = 1 + 0.08 * ease_in_out(seg(t, T - 0.5, T))
    if z > 1.0005:
        nw, nh = int(W * z), int(H * z)
        img = img.resize((nw, nh), Image.BILINEAR).crop(((nw - W) // 2, (nh - H) // 2, (nw - W) // 2 + W, (nh - H) // 2 + H))
    return img

def s_name(t, T):
    img = Image.new('RGBA', (W, H), BONE + (255,))
    guides(img, 1 - ease_out(seg(t, 0, 0.6)))
    a1 = ease_out(seg(t, 0.0, 0.4))
    center_text(img, "I'm", F('InterDisplay-SemiBold.otf', 54), 170 - 20 * (1 - a1), INK, a1)
    a2 = ease_out(seg(t, 0.2, 0.7))
    center_text(img, 'Engin ÇIRPAN', F('InterDisplay-Bold.otf', 88), 236 + 30 * (1 - a2), INK, a2)
    a3 = ease_out(seg(t, 0.45, 0.9))
    center_text(img, 'CREATOR  &  DEVELOPER  OF  JUZZIO', M(17), 352, (90, 70, 170), a3)
    # fotoğraf kartı aşağıdan gelir
    p = back(seg(t, 0.55, 1.5), 1.2)
    top = lerp(H + 40, 420, p)
    box = (90, top, W - 90, top + 760)
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle([box[0] + 6, box[1] + 26, box[2] - 6, box[3] + 26], 44, fill=(40, 20, 90, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
    rounded_photo(img, box, 44, zoom=1.0 + 0.06 * seg(t, 0.5, T), focus=(0.62, 0.36))
    # cam rozet
    if top < H - 100:
        g = (box[0] + 22, box[1] + 22, box[0] + 300, box[1] + 76)
        glass(img, g, radius=27, a=60, blur=10)
        dd = ImageDraw.Draw(img); dd.ellipse([g[0] + 18, g[1] + 21, g[0] + 30, g[1] + 33], fill=(52, 199, 89))
        put_text(img, (g[0] + 42, g[1] + 15), "Juzzio'nun yapımcısı", F('Inter-SemiBold.otf', 21), WHITE)
    return img

def s_role(t, T):
    img = Image.new('RGBA', (W, H), DEEP + (255,))
    a = ease_out(seg(t, 0, 0.35))
    put_text(img, (40, 60), 'ROLE', M(15), (150, 140, 200), a)
    put_text(img, (W - 40, 60), '01 / 04', M(15), (150, 140, 200), a, anchor='ra')
    f = F('InterDisplay-Bold.otf', 66)
    lines = ['Founder', '& Developer']
    for i, s in enumerate(lines):
        ai = ease_out(seg(t, 0.12 + 0.18 * i, 0.6 + 0.18 * i))
        center_text(img, s, f, 540 + i * 84 + 40 * (1 - ai), WHITE, ai)
    d = ImageDraw.Draw(img)
    if t > 0.8 and int(t * 3) % 2 == 0:
        d.rectangle([W / 2 + 205, 650, W / 2 + 221, 666], fill=LIME)
    a2 = ease_out(seg(t, 0.9, 1.4))
    center_text(img, 'Flutter · Supabase · Post-Quantum', M(18), 760, (170, 160, 230), a2)
    return img

BG_INDIGO = gradient_bg((40, 26, 110), (16, 10, 48))
BLOBS = [(160, 300, 260, (123, 92, 255), 120, 0.7), (600, 980, 300, (60, 90, 255), 110, 0.5), (520, 260, 180, (212, 255, 79), 40, 0.9)]

def rings(img, cx, cy, t, alpha):
    d = ImageDraw.Draw(img)
    for i, r in enumerate((150, 230, 320)):
        a = int(70 * alpha * (1 - i * 0.2))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, a), width=1)
    ang = t * 1.4
    for i, r in enumerate((150, 230, 320)):
        x = cx + r * math.cos(ang * (1 + i * 0.3)); y = cy + r * math.sin(ang * (1 + i * 0.3))
        d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=LIME + (int(220 * alpha),))

def s_craft(t, T):
    img = aurora(BG_INDIGO, BLOBS, t)
    rings(img, W / 2, 640, t, ease_out(seg(t, 0, 0.5)))
    words = [('Code.', 0.1), ('Design.', 0.75), ('Security.', 1.4)]
    for i, (w_, st) in enumerate(words):
        p = ease_out(seg(t, st, st + 0.45)); out = ease_in_out(seg(t, st + 0.55, st + 0.75)) if i < 2 else 0
        if p <= 0: continue
        center_text(img, w_, F('InterDisplay-Bold.otf', 92), 585 + 40 * (1 - p) - 40 * out, WHITE, p * (1 - out))
    p = ease_out(seg(t, 2.05, 2.6))
    if p > 0:
        center_text(img, 'and yes, I like', F('InterDisplay-Medium.otf', 54), 820 + 20 * (1 - p), WHITE, p)
        center_text(img, 'to ship.', F('InterDisplay-Bold.otf', 62), 884 + 20 * (1 - p), LIME, p)
    return img

DISC = ['Mobile Apps', 'Realtime Calls', 'Live Translation', 'Post-Quantum E2EE', 'Glass UI', 'Motion Design',
        'Supabase & RLS', 'Product Design', 'Offline-first', 'Edge Functions']

def s_wheel(t, T):
    img = aurora(BG_INDIGO, BLOBS, t + 3)
    a = ease_out(seg(t, 0, 0.3))
    put_text(img, (40, 60), 'DISCIPLINES', M(15), (180, 170, 230), a)
    put_text(img, (W - 40, 60), '02 / 04', M(15), (180, 170, 230), a, anchor='ra')
    put_text(img, (56, 625), 'I build', F('InterDisplay-SemiBold.otf', 40), WHITE, a)
    d = ImageDraw.Draw(img); d.ellipse([196, 641, 208, 653], fill=LIME + (int(255 * a),))
    pos = ease_in_out(seg(t, 0.35, T - 0.3)) * (len(DISC) - 1)
    for i, s in enumerate(DISC):
        k = i - pos
        if abs(k) > 3.6: continue
        y = 646 + 62 * math.sin(clamp(k / 4, -1, 1) * math.pi / 2) * 3.4
        sc = 1 - 0.18 * min(abs(k), 3)
        al = a * (1 - min(abs(k), 3.6) / 3.8)
        sel = abs(k) < 0.5
        f = F('InterDisplay-SemiBold.otf', int(40 * sc))
        col = LIME if sel else WHITE
        layer = Image.new('RGBA', img.size, (0, 0, 0, 0)); dd = ImageDraw.Draw(layer)
        dd.text((240, y), s, font=f, fill=col + (int(255 * clamp(al)),), anchor='lm')
        # hafif eğik (3B tekerlek)
        img.alpha_composite(layer)
    return img

def s_stats(t, T):
    base = gradient_bg((22, 14, 58), (8, 6, 22))
    img = aurora(base, [(200, 400, 280, (123, 92, 255), 110, 0.6), (560, 1000, 260, (212, 255, 79), 45, 0.8)], t)
    a = ease_out(seg(t, 0, 0.3))
    put_text(img, (40, 60), 'NUMBERS', M(15), (170, 160, 220), a)
    put_text(img, (W - 40, 60), '03 / 04', M(15), (170, 160, 220), a, anchor='ra')
    center_text(img, 'Built solo.', F('InterDisplay-Bold.otf', 66), 150 + 20 * (1 - a), WHITE, a)
    cards = [('486', 'database & security tests'), ('195', 'Dart source files'), ('224', 'interface languages'), ('ML-KEM-768', 'post-quantum hybrid E2EE')]
    for i, (num, label) in enumerate(cards):
        p = back(seg(t, 0.25 + 0.22 * i, 0.85 + 0.22 * i), 1.1)
        if p <= 0: continue
        y = 300 + i * 220 + 60 * (1 - p)
        box = (70, y, W - 70, y + 186)
        glass(img, box, radius=34, a=34, blur=16)
        cnt = str(int(int(num) * ease_out(seg(t, 0.35 + 0.22 * i, 1.3 + 0.22 * i)))) if num.isdigit() else num
        put_text(img, (110, y + 30), cnt, F('InterDisplay-Bold.otf', 84 if num.isdigit() else 64), LIME if i % 2 == 0 else WHITE, clamp(p))
        put_text(img, (112, y + 128), label, F('Inter-Medium.otf', 25), (215, 210, 240), clamp(p))
    return img

def s_logo(t, T):
    img = gradient_bg((70, 40, 170), (24, 14, 70))
    img = aurora(img, [(360, 640, 300, (123, 92, 255), 120, 0.6)], t)
    d = ImageDraw.Draw(img)
    cx, cy, R = W / 2, 560, 150
    draw = ease_out(seg(t, 0, 1.0))
    for (ox, oy) in ((0, -R), (R, 0), (0, R), (-R, 0)):
        rr = R * draw
        d.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], outline=(255, 255, 255, 70), width=1)
    rr = R * draw
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(255, 255, 255, 110), width=1)
    for (ox, oy) in ((0, -R), (R, 0), (0, R), (-R, 0)):
        d.line([cx + ox - 6, cy + oy, cx + ox + 6, cy + oy], fill=(255, 255, 255, 150)); d.line([cx + ox, cy + oy - 6, cx + ox, cy + oy + 6], fill=(255, 255, 255, 150))
    p = back(seg(t, 0.6, 1.4), 1.5)
    if p > 0:
        s = int(250 * p)
        lg = LOGO.resize((max(s, 1), max(s, 1)), Image.LANCZOS)
        glow = Image.new('RGBA', img.size, (0, 0, 0, 0)); ImageDraw.Draw(glow).ellipse([cx - s * 0.7, cy - s * 0.7, cx + s * 0.7, cy + s * 0.7], fill=LIME + (int(70 * clamp(p)),))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
        img.alpha_composite(lg, (int(cx - s / 2), int(cy - s / 2)))
    a = ease_out(seg(t, 1.2, 1.8))
    center_text(img, 'Juzzio', F('InterDisplay-Bold.otf', 76), 900 + 20 * (1 - a), WHITE, a)
    center_text(img, 'Talk to anyone. In any language.', F('Inter-Medium.otf', 28), 992 + 20 * (1 - a), (220, 215, 250), a)
    return img

def s_end(t, T):
    img = Image.new('RGBA', (W, H), DEEP + (255,))
    d = ImageDraw.Draw(img)
    a = ease_out(seg(t, 0, 0.5))
    for x in (90, W - 90): d.line([(x, 0), (x, H)], fill=(255, 255, 255, int(28 * a)))
    for y in (560, 700): d.line([(0, y), (W, y)], fill=(255, 255, 255, int(28 * a)))
    # küçük yuvarlak fotoğraf
    p = back(seg(t, 0.0, 0.7), 1.2)
    s = int(170 * p)
    if s > 4:
        ph = Image.new('RGBA', (s, s)); rounded_photo(ph, (0, 0, s, s), s // 2, zoom=1.35, focus=(0.66, 0.30))
        ring = Image.new('RGBA', img.size, (0, 0, 0, 0)); ImageDraw.Draw(ring).ellipse([W / 2 - s / 2 - 6, 330 - 6, W / 2 + s / 2 + 6, 330 + s + 6], outline=LIME + (230,), width=4)
        img.alpha_composite(ring)
        img.alpha_composite(ph, (int(W / 2 - s / 2), 330))
    a2 = ease_out(seg(t, 0.3, 0.9))
    center_text(img, 'Engin ÇIRPAN', F('InterDisplay-Bold.otf', 82), 580 + 20 * (1 - a2), WHITE, a2)
    center_text(img, 'CREATOR  ·  JUZZIO', M(18), 712, (190, 180, 240), a2)
    a3 = ease_out(seg(t, 0.8, 1.3))
    center_text(img, '@tugkancr', F('InterDisplay-SemiBold.otf', 34), 800, LIME, a3)
    fade = seg(t, T - 0.6, T)
    if fade > 0:
        img.alpha_composite(Image.new('RGBA', img.size, (0, 0, 0, int(255 * fade))))
    return img

SCENES = [('01_hello', s_hello, 3.0), ('02_name', s_name, 3.6), ('03_role', s_role, 2.4), ('04_craft', s_craft, 3.4),
          ('05_wheel', s_wheel, 4.2), ('06_stats', s_stats, 3.8), ('07_logo', s_logo, 3.0), ('08_end', s_end, 3.2)]

def render(name, fn, T):
    tmp = f'{OUT}/{name}.part.mp4'; fin = f'{OUT}/{name}.mp4'
    p = subprocess.Popen(['ffmpeg', '-y', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '24', '-pix_fmt', 'yuv420p', '-r', str(FPS), tmp], stdin=subprocess.PIPE)
    n = int(round(T * FPS))
    for i in range(n):
        p.stdin.write(fn(i / FPS, T).convert('RGB').tobytes())
    p.stdin.close()
    if p.wait() == 0: os.replace(tmp, fin)
    else: sys.exit('render failed ' + name)

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'stills':
        for name, fn, T in SCENES:
            for frac in (0.5, 0.95):
                fn(T * frac, T).convert('RGB').save(f'{OUT}/still_{name}_{int(frac*100)}.jpg', quality=88)
    else:
        only = sys.argv[1:] or [s[0] for s in SCENES]
        for name, fn, T in SCENES:
            if name in only: render(name, fn, T)
