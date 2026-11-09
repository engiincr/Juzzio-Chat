"""Juzzio v0.9.9 — 3D kumaş kıvrımı haritaları (kavisli, asimetrik pli/perde katları).

v0.9.8'deki düz radyal "güneş ışını" çizgilerinin yerine her kıvrım bir Bezier eğrisi
boyunca uzanan, keskin sırtlı ve bir yanında gölge vadisi olan gerçek kumaş katıdır.

  tension : yumruk anı — yumruğun SOL ve SAĞ yanlarında, çentiğe doğru yukarı kavislenen
            2–3'er "kelebek kanadı / kulak" kıstırma döngüsü. Yumruğun altı pürüzsüz kalır.
  drape   : yukarı çekme — kavrama noktasından sol-alta, ortaya ve sağ-alta genişleyerek
            açılan 6 ana perde katı; üst barı (arama, konum, avatar) örter, "Popular Food"
            hizasına kadar iner.

Çıktılar (beyaz RGB, alfa = yoğunluk; Flutter tema rengine boyar):
  <önek>_hi.png  : ışık alan sırtlar
  <önek>_sh.png  : gölge vadileri + ortam kapanması
  <önek>_cov.png : kumaş örtüsü maskesi (sayfa rengiyle yarı saydam örtü)

Haritalar 2x yoğunluktadır. Çapa (anchor) noktaları Dart tarafında sabit olarak tutulur:
  tension : 360x230 mantıksal, çapa (180, 150) = yumruk merkezi
  drape   : 360x340 mantıksal, çapa (180, 22)  = kavrama noktası

Kullanım: python3 folds.py <tension|drape> <çıktı_öneki>
"""
import math
import sys

import numpy as np
from PIL import Image

MODE = sys.argv[1] if len(sys.argv) > 1 else "drape"
OUT = sys.argv[2] if len(sys.argv) > 2 else MODE
S = 2.0
if MODE == "tension":
    LW, LH, AX, AY = 360.0, 230.0, 180.0, 150.0
else:
    LW, LH, AX, AY = 360.0, 340.0, 180.0, 22.0
W, H = int(LW * S), int(LH * S)
ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
X = (xs + 0.5) / S - AX   # çapaya göre mantıksal koordinat (x sağa, y aşağı)
Y = (ys + 0.5) / S - AY


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def bezier(p0, p1, p2, p3, n=72):
    t = np.linspace(0, 1, n)[:, None]
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def curve_field(pts):
    """Her piksel için eğriye işaretli uzaklık ve eğri parametresi (0..1). Bellek için parça parça."""
    a = pts[:-1]
    b = pts[1:]
    ab = b - a
    L2 = (ab ** 2).sum(1)
    seg = np.sqrt(L2)
    cum = np.concatenate([[0], np.cumsum(seg)])
    PXa, PYa = X.ravel(), Y.ravel()
    sd = np.empty(PXa.size)
    uu = np.empty(PXa.size)
    for s0 in range(0, PXa.size, 40000):
        px = PXa[s0:s0 + 40000, None]
        py = PYa[s0:s0 + 40000, None]
        t = np.clip(((px - a[:, 0]) * ab[:, 0] + (py - a[:, 1]) * ab[:, 1]) / L2, 0, 1)
        cx = a[:, 0] + t * ab[:, 0]
        cy = a[:, 1] + t * ab[:, 1]
        d2 = (px - cx) ** 2 + (py - cy) ** 2
        i = d2.argmin(1)
        r = np.arange(len(i))
        cross = ab[i, 0] * (py[:, 0] - cy[r, i]) - ab[i, 1] * (px[:, 0] - cx[r, i])
        sd[s0:s0 + 40000] = np.sign(cross) * np.sqrt(d2[r, i])
        uu[s0:s0 + 40000] = (cum[i] + t[r, i] * seg[i]) / cum[-1]
    return sd.reshape(H, W), uu.reshape(H, W)


def pleat(pts, amp, w0, w1, side, valley=0.55, u_in=0.06, u_out=0.92):
    """Keskin sırtlı kumaş katı: sırt + bir yanda daha derin gölge vadisi (asimetri)."""
    sd, u = curve_field(pts)
    w = w0 + (w1 - w0) * u
    env = smoothstep(0.0, u_in, u) * (1 - smoothstep(u_out, 1.0, u))
    env *= 0.55 + 0.45 * np.sin(math.pi * np.clip(u * 0.9 + 0.05, 0, 1))
    crest = np.exp(-np.abs(sd) / w * 1.7)                        # keskin tepe
    body = np.exp(-(sd / (w * 1.6)) ** 2)                         # yumuşak omuz
    h = amp * (0.55 * crest + 0.45 * body)
    vd = np.exp(-((sd - side * w * 1.9) / (w * 0.95)) ** 2)       # yanındaki vadi
    h -= amp * valley * vd
    return h * env, env * body


rng = np.random.default_rng(23 if MODE == "drape" else 41)
h = np.zeros((H, W))
cover = np.zeros((H, W))

if MODE == "tension":
    # Kelebek kanadı kıstırma döngüleri: yumruğun yanından dışarı çıkar, yukarı (çentiğe) kıvrılır.
    for side in (-1, 1):
        for k in range(3):
            j = rng.normal(0, 1, 4)
            x0 = side * (28 + 3 * k)
            y0 = 6 - 9 * k + j[0]
            p0 = np.array([x0, y0])
            p1 = np.array([side * (62 + 16 * k + 4 * j[1]), 18 - 4 * k])
            p2 = np.array([side * (92 + 22 * k + 5 * j[2]), -18 - 14 * k])
            p3 = np.array([side * (70 + 26 * k + 4 * j[3]), -62 - 22 * k + 3 * j[0]])
            amp = (10.5 - 2.4 * k) * (1.0 if side < 0 else 0.92)
            hh, cv = pleat(bezier(p0, p1, p2, p3), amp, 2.2, 9.0 - k, side=-side, valley=0.6,
                           u_in=0.16, u_out=0.80)
            h += hh
            cover = np.maximum(cover, cv)
    # yumruğun içine toplanan kumaş: yan kenarlarda kısa sıkışma, altta pürüzsüz
    below = smoothstep(4, 30, Y)        # yumruğun altı: kıvrım yok, pürüzsüz
    h *= 1 - below
    cover *= 1 - below
else:
    # 6 ana perde katı: sol-alt → orta → sağ-alt; uzunluk ve kavis asimetrik
    ends = [(-176, 150), (-118, 252), (-44, 314), (30, 304), (104, 240), (172, 138)]
    amps = [14.0, 17.0, 19.0, 18.0, 16.0, 13.0]
    for k, (ex, ey) in enumerate(ends):
        j = rng.normal(0, 1, 4)
        p0 = np.array([ex * 0.07, 7 + j[0]])
        bend = (1 if k % 2 == 0 else -1) * (38 + 7 * j[1])
        dirv = np.array([ex, ey]) / math.hypot(ex, ey)
        perp = np.array([-dirv[1], dirv[0]])
        p1 = np.array([ex * 0.22, ey * 0.30]) + perp * bend
        p2 = np.array([ex * 0.62, ey * 0.66]) - perp * bend * 0.75
        p3 = np.array([ex, ey])
        hh, cv = pleat(bezier(p0, p1, p2, p3), amps[k] * (0.9 + 0.1 * j[2]), 3.6, 23.0 + 3 * j[3],
                       side=(1 if k < 3 else -1), valley=0.62, u_in=0.05, u_out=0.86)
        h += hh
        cover = np.maximum(cover, cv)
        # aradaki ince ikincil kırışık
        if k < len(ends) - 1:
            nx, ny = ends[k + 1]
            q3 = np.array([(ex + nx) * 0.5, (ey + ny) * 0.5 * 0.72])
            q0 = np.array([0.0, 12.0])
            q1 = q3 * 0.35 + perp * bend * 0.3
            q2 = q3 * 0.7
            hh2, _ = pleat(bezier(q0, q1, q2, q3), amps[k] * 0.30, 2.0, 9.0, side=1, valley=0.4,
                           u_in=0.12, u_out=0.7)
            h += hh2
    # kavrama noktasında toplanma; çapanın üstünde (çentiğe doğru) kıvrım yok
    rr = np.hypot(X, Y - 4)
    h += 8.0 * np.exp(-(rr / 14.0) ** 2)
    above = smoothstep(-8, 6, Y)
    h *= above
    cover *= above
    # örtü: perde katlarının arasını da dolduran yumuşak çarşaf zarfı
    ang = np.arctan2(Y, X)
    rad = np.hypot(X, Y)
    reach = 150 + 165 * np.sin(np.clip(ang, 0, math.pi)) ** 1.4
    sheet = (1 - smoothstep(reach * 0.70, reach * 1.02, rad)) * smoothstep(-6, 10, Y)
    cover = np.maximum(cover, sheet * 0.85)


def gblur(a, s):
    k = np.arange(-3 * s, 3 * s + 1)
    g = np.exp(-(k / s) ** 2 / 2)
    g /= g.sum()
    a = np.apply_along_axis(lambda v: np.convolve(v, g, mode="same"), 1, a)
    return np.apply_along_axis(lambda v: np.convolve(v, g, mode="same"), 0, a)


# normaller + ışık (sol üstten)
gy, gx = np.gradient(h * S * 0.5)
n = np.stack([-gx, -gy, np.full_like(h, 1.0)], axis=-1)
n /= np.linalg.norm(n, axis=-1, keepdims=True)
Lv = np.array([-0.40, -0.70, 0.59])
Lv /= np.linalg.norm(Lv)
lam = n @ Lv - Lv[2]
hb = gblur(h, 9)
amp_ref = max(h.max(), 1e-3)
ao = np.clip((hb - h) / (amp_ref * 0.45), 0, 1)

edge = np.clip(np.minimum(np.minimum(xs, W - 1 - xs) / (W * 0.04), (H - 1 - ys) / (H * 0.10)), 0, 1)
r0 = np.hypot(X, Y - (0 if MODE == "drape" else 0))
core = smoothstep(4, 16, r0) if MODE == "drape" else smoothstep(20, 32, np.hypot(X / 1.2, Y))
hi = np.clip(lam * 2.6, 0, 1) ** 0.85 * edge * core
sh = np.clip(np.clip(-lam * 2.4, 0, 1) * 0.80 + ao * 0.60, 0, 1) * edge * core
cover = gblur(cover, 4) * edge


def save(a, path):
    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[..., :3] = 255
    img[..., 3] = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path, optimize=True)


save(hi, f"{OUT}_hi.png")
save(sh, f"{OUT}_sh.png")
save(cover, f"{OUT}_cov.png")
print(OUT, f"{W}x{H}", "hi", hi.max().round(2), "sh", sh.max().round(2), "cov", cover.max().round(2))
