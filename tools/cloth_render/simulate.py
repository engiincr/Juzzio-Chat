"""JuzzioClothRefresh (lib/widgets/juzzio_cloth_refresh.dart, v0.9.9) faz motoru + painter'ının
birebir Python kopyası — Flutter derlemeden animasyonu kare kare doğrulamak için.
Aynı geometri (JuzzioClothGeometry), aynı sabitler, aynı eğriler, aynı çizim sırası:
  kumaş örtüsü → gölge vadileri → sırtlar → el gölgesi → el (çentik altına maskeli) → siyah çentik.

Kullanım: python3 simulate.py <arka_plan.png> <çıktı_klasörü> [dark]
"""
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "cloth")
BG = sys.argv[1]
OUTDIR = sys.argv[2]
DARK = len(sys.argv) > 3 and sys.argv[3] == "dark"
os.makedirs(OUTDIR, exist_ok=True)

DPR = 2.0
WL, HL = 360, 780              # mantıksal ekran (iPhone oranı)
TOP_INSET = 47.0
FPS = 30

# ---- JuzzioClothGeometry ----
ISL_W = min(max(WL * 0.32, 100.0), 130.0)
ISL_H = min(max(TOP_INSET * 0.68, 26.0), 37.0)
ISL_CY = max(TOP_INSET * 0.5 if TOP_INSET > 0 else 16.0, ISL_H / 2 + 4)
ISL_BOT = ISL_CY + ISL_H / 2
K = ISL_W / 115.0
SPRITE = (300 * K, 200 * K)
ROOT_IN = (150 * K, 12 * K)
OPEN_TIP = 150.3 * K
FIST_CY = 120 * K
FIST_LOW = 145.7 * K
MAX_VIS = ISL_CY + OPEN_TIP - ISL_BOT
CONTENT_TOP = TOP_INSET
REST = min(max(ISL_CY + OPEN_TIP + 24 - CONTENT_TOP, 140.0), 155.0)
THRESH = REST * 0.80
FOLD_K = WL / 360.0

TENSION = dict(size=(360, 230), anchor=(180, 150))
DRAPE = dict(size=(360, 340), anchor=(180, 22))
SWING_ANGLES = [-15, -10, -5, 0, 5, 10, 15, 20, 25]
CLENCH, YANK, SMOOTH = 0.30, 0.50, 0.25
T_STRENGTH, D_STRENGTH = 1.6, 1.5

RIDGE = (0x22, 0x26, 0x30) if DARK else (0xFF, 0xFF, 0xFF)
VALLEY = (0x07, 0x08, 0x0B) if DARK else (0xC8, 0xCD, 0xD6)
SHADOW = (0, 0, 0, 0.45) if DARK else (0x8C, 0x93, 0xA3, 0.30)


def ss(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def ease_in(u):  # Curves.easeIn ≈ cubic(0.42,0,1,1)
    return u ** 2


def ease_in_cubic(u):
    return u ** 3


def ease_out_cubic(u):
    return 1 - (1 - u) ** 3


def ease_out(u):
    return 1 - (1 - u) ** 2


def ease_in_out_cubic(u):
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


def extent(pull):
    return 0.0 if pull <= 0 else 156 * (1 - math.exp(-pull / 167))


def peek(content):
    if content <= 0:
        return 0.0
    return MAX_VIS * min(content / REST, 1.0) ** 1.3


def root_y(reveal):
    return ISL_BOT + reveal - OPEN_TIP


def pendulum(t):
    if t <= 0:
        return 0.0
    keys = [(0.0, 0), (0.30, -15), (0.75, 25), (1.10, -8), (1.40, 0)]
    if t < 1.40:
        for a, b in zip(keys, keys[1:]):
            if a[0] <= t <= b[0]:
                u = (t - a[0]) / (b[0] - a[0])
                return a[1] + (b[1] - a[1]) * ss(u)
    s = t - 1.40
    return 9 * math.sin(s * 2 * math.pi / 1.25) * min(max(math.exp(-s * 0.15), 0.55), 1.0)


def swing_frame(a):
    x = min(max((a - SWING_ANGLES[0]) / 5, 0), len(SWING_ANGLES) - 1)
    i0 = int(math.floor(x))
    i1 = min(i0 + 1, len(SWING_ANGLES) - 1)
    return i0, i1, x - i0


class Spring:
    def __init__(self, x, target, k, c):
        self.x, self.v, self.t, self.k, self.c = x, 0.0, target, k, c

    def step(self, dt):
        for _ in range(8):
            h = dt / 8
            a = -self.k * (self.x - self.t) - self.c * self.v
            self.v += a * h
            self.x += self.v * h
        return self.x


def load(n):
    return Image.open(os.path.join(ASSETS, n + ".png")).convert("RGBA")


def _sc(im):
    return im.resize((int(round(SPRITE[0] * DPR)), int(round(SPRITE[1] * DPR))), Image.LANCZOS)


swing_imgs = [_sc(load(f"hand_s{i}")) for i in range(9)]
curl_imgs = [_sc(load(f"hand_c{i}")) for i in range(8)]
folds = {k: load(k) for k in [f"fold_{m}_{p}" for m in ("tension", "drape") for p in ("hi", "sh", "cov")]}

W, H = int(WL * DPR), int(HL * DPR)
bg = Image.open(BG).convert("RGBA").resize((W, H))
arr = np.array(bg)
# referans görüntüdeki gömülü (gri) çentiği ve sarkaç noktasını sil — çentiği painter çizer
sbg = arr[int(50 / 1.0), int(215)].copy()
arr[10:100, 215:505] = sbg
pbg = arr[300, 520].copy()
arr[305:365, 415:475] = pbg
bg = Image.fromarray(arr)
status = bg.crop((0, 0, W, int(TOP_INSET * DPR)))
page = bg.crop((0, int(TOP_INSET * DPR), W, H))
base_col = tuple(int(v) for v in pbg[:3]) + (255,)
CLOTH = tuple(int(v) for v in pbg[:3])


def tinted(img, rgb, alpha):
    a = np.array(img)[..., 3].astype(np.float32) / 255.0
    out = np.zeros(a.shape + (4,), dtype=np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = rgb
    out[..., 3] = np.clip(a * min(max(alpha, 0), 1) * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def draw_fold(layer, name, spec, at, sx, sy, amount, strength, cover_alpha):
    w, h = spec["size"]
    ax, ay = spec["anchor"]
    x0, y0 = at[0] - ax * sx, at[1] - ay * sy
    size = (max(int(w * sx * DPR), 1), max(int(h * sy * DPR), 1))
    pos = (int(round(x0 * DPR)), int(round(y0 * DPR)))
    op = amount * strength
    passes = [(f"fold_{name}_cov", CLOTH, amount * cover_alpha)]
    if op > 1:
        passes.append((f"fold_{name}_sh", VALLEY, op - 1))
    passes += [(f"fold_{name}_sh", VALLEY, op), (f"fold_{name}_hi", RIDGE, op)]
    for key, col, al in passes:
        _composite_clipped(layer, tinted(folds[key].resize(size, Image.BILINEAR), col, al), pos)


def _composite_clipped(layer, im, pos):
    tmp = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    tmp.paste(im, pos)
    layer.alpha_composite(tmp)


def sprite_layer(img, root, rot_deg, alpha=1.0):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    im = img
    if alpha < 0.999:
        im = img.copy()
        im.putalpha(Image.eval(img.getchannel("A"), lambda v: int(v * alpha)))
    pos = (int(round((root[0] - ROOT_IN[0]) * DPR)), int(round((root[1] - ROOT_IN[1]) * DPR)))
    _composite_clipped(lay, im, pos)
    if abs(rot_deg) > 1e-3:
        # Flutter: canvas.rotate(-corr) (saat yönü tersine) ≡ PIL rotate(+corr)
        lay = lay.rotate(rot_deg, center=(root[0] * DPR, root[1] * DPR), resample=Image.BICUBIC)
    return lay


def frames_for(sc):
    if sc["curl"] > 0.001:
        x = min(max(sc["curl"], 0), 1) * 7
        i0 = int(math.floor(x))
        i1 = min(i0 + 1, 7)
        f = x - i0
        out = [(curl_imgs[i0], 0.0, 1.0)]
        if f > 0.02 and i1 != i0:
            out.append((curl_imgs[i1], 0.0, f))
        return out
    i0, i1, f = swing_frame(sc["angle"])
    corr = lambda i: (sc["angle"] - SWING_ANGLES[i]) * 0.85
    out = [(swing_imgs[i0], corr(i0), 1.0)]
    if f > 0.02 and i1 != i0:
        out.append((swing_imgs[i1], corr(i1), f))
    return out


def scene_frame(sc, content):
    frame = Image.new("RGBA", (W, H), base_col)
    frame.alpha_composite(page, (0, int(round((TOP_INSET + content) * DPR))))
    frame.alpha_composite(status, (0, 0))
    cx = WL / 2
    root = (cx, root_y(sc["reveal"]))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if sc["drape"] > 0.01:
        draw_fold(layer, "drape", DRAPE, (cx, sc["grabY"]), FOLD_K, FOLD_K * (1 + sc["stretch"]), sc["drape"], D_STRENGTH, 0.50)
    if sc["tension"] > 0.01:
        k = FOLD_K * (0.80 + 0.20 * sc["tension"])
        draw_fold(layer, "tension", TENSION, (cx, root[1] + FIST_CY), k, k, sc["tension"], T_STRENGTH, 0.40)
    if sc["reveal"] > -2:
        fr = frames_for(sc)
        rad = math.radians(sc["angle"])
        off = ((8 + 10 * math.sin(rad) + 16 * sc["lift"]) * K, (12 + 18 * sc["lift"]) * K)
        sa = SHADOW[3] * (1 - 0.8 * sc["lift"])
        shl = sprite_layer(tinted(fr[0][0], SHADOW[:3], sa), (root[0] + off[0], root[1] + off[1]), fr[0][1])
        shl = shl.filter(ImageFilter.GaussianBlur((6 + 8 * sc["lift"]) * DPR / 2))
        layer.alpha_composite(shl)
        for img, rot, al in fr:
            layer.alpha_composite(sprite_layer(img, root, rot, al))
    # maske: yalnız çentiğin alt kenarının altı
    m = np.array(layer.getchannel("A"))
    m[: int(round((ISL_BOT - 0.5) * DPR))] = 0
    layer.putalpha(Image.fromarray(m))
    frame.alpha_composite(layer)
    # Dynamic Island: tam siyah, en üst katman
    if True:  # cihazın kendi çentiği hep oradadır; painter da bindirmeyi tam opak çizer
        isl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(isl)
        box = [(cx - ISL_W / 2) * DPR, (ISL_CY - ISL_H / 2) * DPR, (cx + ISL_W / 2) * DPR, (ISL_CY + ISL_H / 2) * DPR]
        d.rounded_rectangle(box, radius=ISL_H / 2 * DPR, fill=(0, 0, 0, 255))
        frame.alpha_composite(isl)
    return frame


# ---------------------------------------------------------------------------
# Zaman çizelgesi: 0,8 sn çekme (önce parmak uçları) → bırak → 1,0 sn yenileme →
# sarkaç merkezden geçince yumruk → yukarı çek → ütüleme → bekleme
# ---------------------------------------------------------------------------
dt = 1 / FPS
PULL_T = 0.8
frames = []
log = []
phase, t_phase, total = "pull", 0.0, 0.0
content = 0.0
spring = None
refresh_time = 1.0
prev_angle = 0.0
yank_from = yank_low = 0.0
blank = dict(reveal=-4, angle=0, curl=0, lift=0, tension=0, drape=0, stretch=0, grabY=0, island=0)
sc = dict(blank)
while total < PULL_T + 1.4 + CLENCH + YANK + SMOOTH + 0.45:
    if phase == "pull":
        pull = 560 * min(total / PULL_T, 1.0) ** 1.6
        content = extent(pull)
        sc = dict(blank, reveal=peek(content), island=min(content / 10, 1))
        if total + dt > PULL_T:
            assert content >= THRESH, (content, THRESH)
            phase, t_phase = "swing", 0.0
            spring = Spring(content, REST, 300, 36)
    else:
        t_phase += dt
        t = t_phase
        if phase == "swing":
            content = spring.step(dt)
            ang = pendulum(t)
            sc = dict(blank, reveal=peek(content), angle=ang, island=1)
            crossed = abs(ang) < 1.5 or (prev_angle != 0 and math.copysign(1, ang) != math.copysign(1, prev_angle))
            prev_angle = ang
            if t >= refresh_time and t >= 1.40 and crossed:
                content = REST
                phase, t_phase = "clench", 0.0
        elif phase == "clench":
            u = min(t / CLENCH, 1)
            content = REST
            sc = dict(blank, reveal=MAX_VIS + 8 * ease_out(u), curl=ease_in_cubic(u), tension=ease_out(u), island=1)
            if u >= 1:
                yank_from = MAX_VIS + 8
                yank_low = root_y(yank_from) + FIST_LOW
                phase, t_phase = "yank", 0.0
        elif phase == "yank":
            u = min(t / YANK, 1)
            e = ease_in_out_cubic(u)
            hidden = OPEN_TIP - FIST_LOW - 2
            rv = yank_from + (hidden - yank_from) * e
            r = root_y(rv)
            span = yank_low - ISL_BOT
            content = REST * min(max((r + FIST_LOW - ISL_BOT) / span, 0), 1)
            sc = dict(blank, reveal=rv, curl=1, lift=e, tension=1 - min(u / 0.35, 1), drape=ease_out(min(u / 0.30, 1)),
                      stretch=0.25 * e, grabY=max(r + FIST_CY, ISL_BOT), island=1)
            if u >= 1:
                content = 0
                phase, t_phase = "smooth", 0.0
        elif phase == "smooth":
            u = min(t / SMOOTH, 1)
            e = ease_out_cubic(u)
            content = 0
            sc = dict(blank, reveal=0, curl=1, lift=1, drape=1 - e, stretch=0.25 - 0.75 * e, grabY=ISL_BOT, island=1 - ease_in(u))
            if u >= 1:
                phase = "done"
        else:
            content = 0
            sc = dict(blank)
    frames.append(scene_frame(sc, content))
    log.append((round(total, 3), phase, round(content, 1), round(sc["reveal"], 1), round(sc["angle"], 1)))
    total += dt

for i, im in enumerate(frames):
    im.convert("RGB").save(os.path.join(OUTDIR, f"s_{i:03d}.png"))
subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(OUTDIR, "s_%03d.png"),
                "-pix_fmt", "yuv420p", "-vf", "scale=360:-2", os.path.join(OUTDIR, "preview.mp4")], check=True)
print(f"geo: island w={ISL_W:.1f} h={ISL_H:.1f} cy={ISL_CY:.1f} bottom={ISL_BOT:.1f} rest={REST:.1f} thr={THRESH:.1f} maxVis={MAX_VIS:.1f}")
print("frames", len(frames))
with open(os.path.join(OUTDIR, "timeline.txt"), "w") as f:
    for row in log:
        f.write("%s\t%s\tcontent=%s\treveal=%s\tangle=%s\n" % row)
