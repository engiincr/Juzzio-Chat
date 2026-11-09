"""Juzzio v0.9.9 — 3D kil (clay) el/kol sprite render'ı (SDF raymarching).

Birimler mantıksal pikseldir (360 genişlikli ekran); çıktı 3x yoğunluktadır.
Kök (0,0) = çentiğin (Dynamic Island) merkezi; kol buradan aşağı sarkar.

Model:
  • Tombul, kısa kol (genişlik ≈ çentik genişliğinin %55'i), bilekte yumuşak boğum
  • Sarkaç pozu: kök sabit kalır; kol bir yay boyunca bükülür, bilek gecikmeyle daha çok
    döner (eklemli bükülme); sağ zirvede parmaklar yelpaze gibi açılır
  • Parmaklar: 3 boğum, boğum çizgileri (gölge oyukları), parlak 3D tırnaklar
  • Yumruk: proksimal boğumlar izleyiciye dönük yan yana sıralanır (aralarında dikey oyuklar),
    başparmak altta parmakların üzerine sıkılır — asla düz bir topuza dönüşmez
  • Malzeme: sıcak mat şeftali/kil (#F2C2B3 gövde, #DF9F8E boğum gölgeleri, #F9DCD3 tırnak)

Kullanım: python3 hand.py <çıktı.png> --curl C --swing DERECE --spread S
"""
import argparse
import math

import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--curl", type=float, default=0.0)
ap.add_argument("--swing", type=float, default=0.0)
ap.add_argument("--spread", type=float, default=0.0)
ap.add_argument("--px", type=float, default=3.0)
ap.add_argument("--ss", type=int, default=2)
args = ap.parse_args()

# Tuval (mantıksal): x ∈ [-150, 150], y ∈ [-12, 188]; kök (0,0) → tuvalde (150, 12)
X0, X1, Y0, Y1 = -150.0, 150.0, -12.0, 188.0
PX, SS = args.px, args.ss


def lerp(a, b, t):
    return a + (b - a) * t


c = min(max(args.curl, 0.0), 1.0)
ease = c * c * (3 - 2 * c)
spread = min(max(args.spread, 0.0), 1.0)
theta = math.radians(args.swing)


def nrm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / (np.linalg.norm(v) + 1e-12)


# ---------------------------------------------------------------------------
# Kol: kökten bileğe yay boyunca bükülen tombul tüp
# ---------------------------------------------------------------------------
ARM_LEN = 86.0
N_ARM = 9
arm_pts = [np.array([0.0, -14.0, 0.0])]  # çentiğin içine doğru taşar (maskelenir)
arm_pts.append(np.array([0.0, 0.0, 0.0]))
for k in range(1, N_ARM + 1):
    u = k / N_ARM
    phi = theta * (0.30 + 0.70 * u) * 0.80   # kökte az, bilekte çok dönüş (bükülme)
    step = ARM_LEN / N_ARM
    prev = arm_pts[-1]
    arm_pts.append(prev + step * np.array([math.sin(phi), math.cos(phi), 0.0]))


def arm_radius(u):
    # tombul ön kol: ortada hafif şişkin, bilekte boğum
    return 31.5 + 2.2 * math.sin(math.pi * min(u, 1.0)) - 3.0 * max(0.0, (u - 0.85) / 0.15) ** 2


ARM_CAPS = []
for k in range(len(arm_pts) - 1):
    u0 = max(0.0, (k - 1) / N_ARM)
    u1 = max(0.0, k / N_ARM)
    ARM_CAPS.append((arm_pts[k], arm_pts[k + 1], arm_radius(u0), arm_radius(u1)))
WRIST = arm_pts[-1].copy()
arm_dir_end = nrm(arm_pts[-1] - arm_pts[-2])

# ---------------------------------------------------------------------------
# El uzayı: bilekte, kolun ucuna göre ek bükülme (gecikmeli bilek) + öne eğilme (flex)
# ---------------------------------------------------------------------------
hand_rot = theta * 1.05                      # bilek, kolun ucundan daha çok döner
FLEX = math.radians(lerp(16.0, 6.0, ease))   # bilekten öne bükülme (yumrukta az)
YAW = math.radians(-8.0)
cz, sz = math.cos(hand_rot), math.sin(hand_rot)
cf, sf = math.cos(FLEX), math.sin(FLEX)
cy_, sy_ = math.cos(YAW), math.sin(YAW)
# dünya→el uzayı (ters dönüşüm): z etrafında dönüş, sonra yaw, sonra flex geri alınır
Rz_inv = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])   # dünyada +rot = sağa salınım → ters
R_inv = np.array([[1, 0, 0], [0, cf, -sf], [0, sf, cf]]) @ np.array([[cy_, 0, -sy_], [0, 1, 0], [sy_, 0, cy_]]) @ Rz_inv


def to_hand(p):
    return (p - WRIST) @ R_inv.T


# El modeli (bilek orijinde, y aşağı, z izleyiciye)
PALM_C = np.array([0.0, lerp(22.0, 20.0, ease), lerp(0.0, 3.0, ease)])
PALM_R = np.array([lerp(35.0, 36.0, ease), lerp(24.0, 22.0, ease), lerp(19.0, 22.0, ease)])

FX = [-25.0, -8.5, 8.5, 25.0]
FSCALE = [0.82, 1.0, 1.06, 0.94]
F_RAD = (10.2, 9.6, 9.0)
F_LEN = (14.0, 10.0, 8.5)
A_OPEN = (26.0, 26.0, 18.0)
A_FIST = (62.0, 112.0, 88.0)
ANG = [math.radians(lerp(a, b, ease) - spread * 9.0 * (1 - ease)) for a, b in zip(A_OPEN, A_FIST)]

FINGER_SEGS = []   # (a, b, ra, rb, finger_idx, seg_idx)
NAILS = []         # (merkez, eksenler(3x3), yarıçaplar)
JOINTS = []        # (nokta, yön, dorsal) — boğum çizgisi gölgeleri için
for i, x in enumerate(FX):
    s = FSCALE[i]
    base = np.array([x * lerp(1.0, 0.95, ease), PALM_C[1] + lerp(19.0, 15.0, ease), lerp(-2.0, 2.0, ease)])
    fan = (x / 25.0) * (lerp(0.12, 0.03, ease) + spread * 0.42 * (1 - ease))   # yelpaze açılması
    pts = [base]
    acc = 0.0
    dirs = []
    for j in range(3):
        acc += ANG[j]
        d = np.array([math.sin(fan) * math.cos(acc), math.cos(fan) * math.cos(acc), -math.sin(acc)])
        dirs.append(d)
        pts.append(pts[-1] + F_LEN[j] * s * d)
    for j in range(3):
        rb = F_RAD[min(j + 1, 2)] * (0.97 if j == 2 else 1.0)
        FINGER_SEGS.append((pts[j], pts[j + 1], F_RAD[j], rb, i, j))
    # tırnak: son boğumun sırt (dorsal) tarafında, uca yakın, hafif kabarık
    d = dirs[2]
    side = nrm(np.cross(d, np.array([0.0, 0.0, 1.0])) if abs(d[2]) < 0.98 else np.array([1.0, 0.0, 0.0]))
    dorsal = nrm(np.cross(side, d))
    if dorsal[2] < 0:
        dorsal = -dorsal
        side = -side
    r3 = F_RAD[2]
    nc = pts[3] - d * (r3 * 0.45) + dorsal * (r3 * 0.86)
    NAILS.append((nc, np.stack([side, d, dorsal]), np.array([r3 * 0.62, r3 * 0.74, r3 * 0.30])))
    JOINTS.append((pts[1], dirs[0], dirs[1]))
    JOINTS.append((pts[2], dirs[1], dirs[2]))

# Başparmak (sağda): açıkta yana-aşağı; yumrukta altta parmakların önüne sıkılır
tb = np.array([lerp(30.0, 24.0, ease), lerp(22.0, 36.0, ease), lerp(4.0, 10.0, ease)])
d_open = nrm([0.86 + 0.12 * spread, 0.46 - 0.15 * spread, -0.08])
d_fist = nrm([-0.80, 0.50, 0.34])
td = nrm(d_open * (1 - ease) + d_fist * ease)
t1 = tb + 15.0 * td
td2 = nrm(td + np.array([lerp(-0.05, -0.30, ease), lerp(0.30, 0.15, ease), lerp(-0.20, 0.10, ease)]))
t2 = t1 + 12.0 * td2
THUMB = [(tb, t1, 11.2, 10.2), (t1, t2, 10.2, 9.2)]
side_t = nrm(np.cross(td2, np.array([0.0, 0.0, 1.0])))
dors_t = nrm(np.cross(side_t, td2))
if dors_t[2] < 0:
    dors_t, side_t = -dors_t, -side_t
NAILS.append((t2 - td2 * 4.4 + dors_t * 7.9, np.stack([side_t, td2, dors_t]), np.array([5.9, 6.8, 2.8])))
JOINTS.append((t1, td, td2))


# ---------------------------------------------------------------------------
# SDF ilkelleri
# ---------------------------------------------------------------------------
def sd_capsule(p, a, b, ra, rb):
    pa = p - a
    ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    d = np.linalg.norm(pa - h[:, None] * ba, axis=1)
    return d - (ra + (rb - ra) * h)


def sd_ellipsoid_local(q, r):
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def sdf_parts(p):
    arm = None
    for cap in ARM_CAPS:
        dc = sd_capsule(p, *cap)
        arm = dc if arm is None else smin(arm, dc, 3.0)
    q = to_hand(p)
    palm = sd_ellipsoid_local(q - PALM_C, PALM_R)
    body = smin(arm, palm, 11.0)
    fingers = None
    for (a, b, ra, rb, _, _) in FINGER_SEGS:
        dc = sd_capsule(q, a, b, ra, rb)
        fingers = dc if fingers is None else smin(fingers, dc, 0.45)  # küçük k → parmak arası oyuklar
    body = smin(body, fingers, 5.5)
    thumb = smin(sd_capsule(q, *THUMB[0]), sd_capsule(q, *THUMB[1]), 2.0)
    body = smin(body, thumb, 6.0)
    nails = None
    for (cn, ax, rr) in NAILS:
        local = (q - cn) @ ax.T
        dn = sd_ellipsoid_local(local, rr)
        nails = dn if nails is None else np.minimum(nails, dn)
    d = smin(body, nails, 0.6)
    return d, nails, q


def sdf(p):
    return sdf_parts(p)[0]


# ---------------------------------------------------------------------------
# Raymarch (ortografik, z ekseni boyunca)
# ---------------------------------------------------------------------------
W = int(round((X1 - X0) * PX))
H = int(round((Y1 - Y0) * PX))
RW, RH = W * SS, H * SS
xs = X0 + (np.arange(RW) + 0.5) / (PX * SS)
ys = Y0 + (np.arange(RH) + 0.5) / (PX * SS)
XX, YY = np.meshgrid(xs, ys)

# 2B sınır kutusu: yalnız şeklin olabileceği pikseller işlenir
allpts = [c[0] for c in ARM_CAPS] + [c[1] for c in ARM_CAPS]
handw = []
inv = R_inv.T
fwd = np.linalg.inv(inv)
for (a, b, *_r) in FINGER_SEGS:
    handw += [a @ fwd + WRIST, b @ fwd + WRIST]
for (a, b, *_r) in THUMB:
    handw += [a @ fwd + WRIST, b @ fwd + WRIST]
handw += [PALM_C @ fwd + WRIST]
P2 = np.array([p[:2] for p in allpts + handw])
bx0, by0 = P2.min(axis=0) - 45
bx1, by1 = P2.max(axis=0) + 45
inside = (XX >= bx0) & (XX <= bx1) & (YY >= by0) & (YY <= by1)

idx_all = np.where(inside.ravel())[0]
ro = np.stack([XX.ravel()[idx_all], YY.ravel()[idx_all], np.full(idx_all.size, 80.0)], axis=1)
t = np.zeros(idx_all.size)
hit = np.zeros(idx_all.size, dtype=bool)
alive = np.ones(idx_all.size, dtype=bool)
for _ in range(80):
    ids = np.where(alive)[0]
    if ids.size == 0:
        break
    p = ro[ids].copy()
    p[:, 2] -= t[ids]
    d = sdf(p)
    t[ids] += d * 0.92
    nh = d < 0.02
    hit[ids[nh]] = True
    alive[ids[nh]] = False
    alive[ids[t[ids] > 160.0]] = False

hi_idx = np.where(hit)[0]
P = ro[hi_idx].copy()
P[:, 2] -= t[hi_idx]

e = 0.12
grad = np.stack([sdf(P + [e, 0, 0]) - sdf(P - [e, 0, 0]),
                 sdf(P + [0, e, 0]) - sdf(P - [0, e, 0]),
                 sdf(P + [0, 0, e]) - sdf(P - [0, 0, e])], axis=1)
Nrm = grad / (np.linalg.norm(grad, axis=1, keepdims=True) + 1e-9)

ao = np.zeros(len(P))
for i, h in enumerate([0.8, 2.0, 3.8, 6.5, 10.0]):
    ao += (h - sdf(P + Nrm * h)) / (2.0 ** i)
ao = np.clip(1.0 - 0.14 * ao, 0.0, 1.0)

_, nail_d, Q = sdf_parts(P)
is_nail = nail_d < 0.35

# boğum çizgileri: eklem düzleminin yakınında sırt tarafında yumuşak gölge oyuğu
crease = np.zeros(len(P))
for (jp, d0, d1) in JOINTS:
    dn = nrm(d0 + d1)
    along = (Q - jp) @ dn
    dist = np.linalg.norm(Q - jp, axis=1)
    crease = np.maximum(crease, np.exp(-(along / 0.9) ** 2) * np.exp(-(dist / 12.0) ** 2))
# bilek boğumu
wa = (P - WRIST) @ arm_dir_end
crease = np.maximum(crease, 0.16 * np.exp(-((wa + 2.0) / 4.5) ** 2) * np.exp(-(np.linalg.norm((P - WRIST)[:, :2], axis=1) / 42.0) ** 4))

# ---------------------------------------------------------------------------
# Gölgelendirme: sıcak mat şeftali kil + alt yüzey saçılımı + parlak tırnak
# ---------------------------------------------------------------------------
L = nrm([-0.42, -0.60, 0.68])
V = np.array([0.0, 0.0, 1.0])
Hh = nrm(L + V)
ndl = Nrm @ L
wrap = np.clip((ndl + 0.22) / 1.22, 0, 1) ** 1.35
sss = np.clip(1.0 - np.abs(ndl), 0, 1) ** 2
rim = np.clip(1.0 - (Nrm @ V), 0, 1) ** 3
fill = np.clip(Nrm @ nrm([0.55, 0.15, 0.8]), 0, 1)

body = np.array([0xF2, 0xC2, 0xB3]) / 255.0
shade = np.array([0xDF, 0x9F, 0x8E]) / 255.0
deep = np.array([0xC4, 0x82, 0x72]) / 255.0
light = np.array([0xFC, 0xE4, 0xDA]) / 255.0
warm = np.array([0xF0, 0x8C, 0x78]) / 255.0
nailc = np.array([0xF9, 0xDC, 0xD3]) / 255.0

col = shade[None] * (1 - wrap[:, None]) + body[None] * wrap[:, None]
col = col * (0.60 + 0.40 * ao[:, None])
col = col * (1 - 0.35 * (1 - ao[:, None]) ** 2) + deep[None] * (0.25 * (1 - ao[:, None]))
col = col * (1 - 0.30 * crease[:, None]) + shade[None] * (0.18 * crease[:, None])
col += light[None] * (0.16 * np.clip(ndl, 0, 1)[:, None])
col += warm[None] * (0.12 * sss[:, None] * ao[:, None])
col += np.array([1.0, 0.94, 0.9])[None] * (0.07 * fill[:, None])
col += np.array([1.0, 0.9, 0.86])[None] * (0.08 * rim[:, None])
spec_body = np.clip(Nrm @ Hh, 0, 1) ** 16 * 0.07
col += spec_body[:, None]
# tırnak: açık ton + belirgin parlaklık + kenarda ince oyuk (AO'dan gelir)
# tırnak çevresi ince oyuk (kütikül): tırnağın hemen dışında hafif koyu halka
groove = np.exp(-((nail_d - 0.75) / 0.45) ** 2) * (nail_d > 0.35)
col = col * (1 - 0.22 * groove[:, None]) + shade[None] * (0.10 * groove[:, None])
ncol = nailc[None] * (0.97 + 0.08 * wrap[:, None]) * (0.95 + 0.05 * ao[:, None]) + np.array([0.02, 0.0, 0.0])[None]
ncol += (np.clip(Nrm @ Hh, 0, 1) ** 28 * 0.42)[:, None]   # parlak (glossy) tırnak yüzeyi
ncol += (np.clip(Nrm @ nrm([-0.3, -0.5, 0.81]), 0, 1) ** 60 * 0.30)[:, None]  # ikinci küçük parıltı
col = np.where(is_nail[:, None], ncol, col)
col = np.clip(col, 0, 1)

img = np.zeros((RH * RW, 4))
gi = idx_all[hi_idx]
img[gi, :3] = col
img[gi, 3] = 1.0
img = img.reshape(RH, RW, 4)
pm = img.copy()
pm[..., :3] *= pm[..., 3:4]
pm = pm.reshape(H, SS, W, SS, 4).mean(axis=(1, 3))
a = pm[..., 3:4]
rgb = np.where(a > 1e-4, pm[..., :3] / np.maximum(a, 1e-4), 0)
out = np.concatenate([rgb, a], axis=2)
Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(args.out, optimize=True)
tipy = max(float((a[..., 0] > 0.5).nonzero()[0].max()) / PX + Y0, 0)
print(args.out, f"curl={c:.2f} swing={args.swing:+.0f} spread={spread:.2f} hits={len(hi_idx)} tipY={tipy:.1f}")
