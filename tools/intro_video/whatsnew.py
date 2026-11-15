#!/usr/bin/env python3
"""Juzzio "1.2.7'den bu yana neler yeni?" videosu (1.2.7 + 1.2.8 + 1.2.9) — 720x1280, 30 fps, ~24 sn.

Güncelleme alan kullanıcılara (1.2.9'dan önceki bir sürümden gelenler) BİR KEZ gösterilir.
Yasal/yönetici özellikleri bu videoda YER ALMAZ (yalnız kullanıcıya dönük yenilikler).
Kullanım:
  python3 tools/juzzio_music_synth.py 25 129 /tmp/wn.wav     # ÖZGÜN müzik (telifsiz)
  python3 tools/intro_video/whatsnew.py tr --music /tmp/wn.wav
  python3 tools/intro_video/whatsnew.py en --music /tmp/wn.wav
  python3 tools/intro_video/whatsnew.py stills tr           # kontrol kareleri
Tüm kareler kodla çizilir (PIL). Görsel olarak yalnız uygulama logosu; bayraklar Noto Color
Emoji (SIL OFL 1.1) ile çizilir. Sosyal medyadan indirilen ses/görsel KULLANILMAZ.
"""
import importlib.util, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('juzzio_intro', os.path.join(HERE, 'intro.py'))
I = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(I)
W, H, FPS = I.W, I.H, I.FPS
F, layer, text_center, glow, aurora, logo_at, rrect = I.F, I.layer, I.text_center, I.glow, I.aurora, I.logo_at, I.rrect
seg, ease_out, back, clamp, ease_io = I.seg, I.ease_out, I.back, I.clamp, I.ease_io
WHITE, MUTED, LIME, VIOLET, PINK, SKY = I.WHITE, I.MUTED, I.LIME, I.VIOLET, I.PINK, I.SKY
EMOJI_FONT = os.path.join(I.ROOT, 'assets/fonts/NotoColorEmoji.ttf')

TEXT = {
    'tr': dict(
        v='Sürüm 1.2.9', q="1.2.7'den bu yana neler yeni?",
        scenes=[
            ('1.2.7', [('🎬', 'Tanıtım videosu', 'İlk girişte 20 saniyede Juzzio'),
                       ('🎂', '3B doğum günü kutlaması', 'Daha uzun, daha görkemli'),
                       ('🌦️', 'Canlı hava teması', 'Saate göre minik simgeler')]),
            ('1.2.8', [('🍿', 'Sinema Parti yenilendi', 'Her bağlantı, 4 kişi, sesli oda'),
                       ('🗣️', 'Canlı çeviri düzeldi', 'Kopunca kendiliğinden bağlanır'),
                       ('📥', 'Medyayı indir, 720p video', 'Titreme yok, daha az veri')]),
            ('1.2.9', [('✨', 'Cam menü ve 7 hızlı tepki', 'Yanıtla · Çevir · İlet · Seç'),
                       ('🎞️', 'Komik hareketli GIF\'ler', 'Sözsüz, kendi dilinde aranır'),
                       ('✉️', 'Mesaj istekleri', 'İstek kutusu ve spam kutusu')]),
            ('1.2.9', [('🎵', 'Sohbette müzik', 'Önizle, profil müziği yap'),
                       ('🌙', 'Gerçek Ay evresi', 'Daha gerçekçi hava teması'),
                       ('📶', 'Daha sağlam aramalar', 'Yeniden bağlanma, 720p → 360p')]),
            ('Düzeltmeler', [('🛠️', 'Çökme ve hata kodları giderildi', 'Emoji adlar, P0001 yerine açık mesaj'),
                             ('💬', 'Tepkiler balonun içinde', 'Sarı çizgi yok, akıcı gönderim'),
                             ('🔒', 'Daha güvenli dosyalar', 'Zararlı dosya ve bağlantı uyarısı')]),
        ],
        thanks='Teşekkürler!', thanksb="Juzzio'yu birlikte büyütüyoruz",
        credits='Katkılarıyla', end='Keyfini çıkar', endb='Juzzio 1.2.9',
    ),
    'en': dict(
        v='Version 1.2.9', q="What's new since 1.2.7?",
        scenes=[
            ('1.2.7', [('🎬', 'Intro video', 'Juzzio in 20 seconds on first sign-in'),
                       ('🎂', '3D birthday celebration', 'Longer and grander'),
                       ('🌦️', 'Live weather theme', 'Tiny icons that follow the hour')]),
            ('1.2.8', [('🍿', 'Cinema Party rebuilt', 'Any link, 4 people, voice room'),
                       ('🗣️', 'Live translation fixed', 'Reconnects by itself'),
                       ('📥', 'Download media, 720p video', 'No flicker, less data')]),
            ('1.2.9', [('✨', 'Glass menu & 7 quick reactions', 'Reply · Translate · Forward · Select'),
                       ('🎞️', 'Funny animated GIFs', 'Wordless, searchable in your language'),
                       ('✉️', 'Message requests', 'Request box and spam box')]),
            ('1.2.9', [('🎵', 'Music in chats', 'Preview it, set as profile music'),
                       ('🌙', 'Real moon phase', 'A more realistic weather theme'),
                       ('📶', 'Sturdier calls', 'Reconnects, 720p → 360p')]),
            ('Fixes', [('🛠️', 'Crashes and error codes fixed', 'Emoji names, clear messages not P0001'),
                       ('💬', 'Reactions inside the bubble', 'No yellow line, smooth sending'),
                       ('🔒', 'Safer files', 'Warnings for harmful files and links')]),
        ],
        thanks='Thank you!', thanksb="We're growing Juzzio together",
        credits='With contributions from', end='Enjoy', endb='Juzzio 1.2.9',
    ),
}
CREDITS = [('@fikret39', '🇹🇷'), ('@ari', '🇺🇸')]

_emoji_cache = {}
def emoji_img(ch, size):
    """Renkli emoji (Noto Color Emoji 109 px bitmap → ölçek)."""
    key = (ch, size)
    if key in _emoji_cache: return _emoji_cache[key]
    f = ImageFont.truetype(EMOJI_FONT, 109)
    im = Image.new('RGBA', (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((8, 8), ch, font=f, embedded_color=True)
    bb = im.getbbox() or (0, 0, 1, 1)
    im = im.crop(bb)
    r = size / max(im.size)
    im = im.resize((max(1, int(im.size[0] * r)), max(1, int(im.size[1] * r))), Image.LANCZOS)
    _emoji_cache[key] = im
    return im

def paste_alpha(img, im, x, y, a):
    if a <= 0: return
    if a < 1:
        im = im.copy(); im.putalpha(im.getchannel('A').point(lambda v: int(v * a)))
    img.alpha_composite(im, (int(x), int(y)))

def s_open(t, T, X):
    img = aurora(t)
    p = back(seg(t, 0.05, 0.8), 1.4)
    glow(img, W / 2, 480, 220 * p + 1, LIME, 0.32 * clamp(p))
    logo_at(img, W / 2, 480, 230 * p)
    a = ease_out(seg(t, 0.6, 1.2))
    # sürüm rozeti
    if a > 0:
        L = layer(); d = ImageDraw.Draw(L)
        f = F('Inter-Bold.otf', 30); tw = d.textlength(X['v'], font=f)
        y = 640 + 20 * (1 - a)
        rrect(d, [(W - tw) / 2 - 26, y, (W + tw) / 2 + 26, y + 60], 30, fill=LIME + (int(255 * a),))
        d.text(((W - tw) / 2, y + 12), X['v'], font=f, fill=(16, 12, 40, int(255 * a)))
        img.alpha_composite(L)
    a2 = ease_out(seg(t, 1.0, 1.7))
    text_center(img, X['q'], F('InterDisplay-Bold.otf', 46), 760 + 18 * (1 - a2), WHITE, a2)
    return img

def feature_scene(label, items, tint_t):
    def s(t, T, X):
        img = aurora(t + tint_t)
        # sürüm rozeti (hangi sürümde geldi)
        ab = ease_out(seg(t, 0.0, 0.4))
        if ab > 0:
            L = layer(); d = ImageDraw.Draw(L)
            f = F('Inter-Bold.otf', 34); tw = d.textlength(label, font=f)
            rrect(d, [(W - tw) / 2 - 30, 196, (W + tw) / 2 + 30, 262], 33, fill=LIME + (int(255 * ab),))
            d.text(((W - tw) / 2, 208), label, font=f, fill=(16, 12, 40, int(255 * ab)))
            img.alpha_composite(L)
        y0 = 320
        for i, (em, title, sub) in enumerate(items):
            a = ease_out(seg(t, 0.15 + i * 0.35, 0.65 + i * 0.35))
            if a <= 0: continue
            y = y0 + i * 250 + 30 * (1 - a)
            L = layer(); d = ImageDraw.Draw(L)
            rrect(d, [70, y, W - 70, y + 200], 40, fill=(255, 255, 255, int(28 * a)), outline=(255, 255, 255, int(70 * a)), width=2)
            rrect(d, [100, y + 46, 208, y + 154], 30, fill=VIOLET + (int(200 * a),))
            maxw = W - 70 - 236 - 24
            fs = 34
            while fs > 22 and d.textlength(title, font=F('Inter-Bold.otf', fs)) > maxw: fs -= 1
            ss = 24
            while ss > 17 and d.textlength(sub, font=F('Inter-Medium.otf', ss)) > maxw: ss -= 1
            d.text((236, y + 52), title, font=F('Inter-Bold.otf', fs), fill=WHITE + (int(255 * a),))
            d.text((236, y + 104), sub, font=F('Inter-Medium.otf', ss), fill=MUTED + (int(255 * a),))
            img.alpha_composite(L)
            paste_alpha(img, emoji_img(em, 64), 122, y + 68, a)
        return img
    return s

def s_thanks(t, T, X):
    img = aurora(t + 11)
    p = back(seg(t, 0.0, 0.7), 1.5)
    glow(img, W / 2, 520, 200, PINK, 0.35 * clamp(p))
    paste_alpha(img, emoji_img('💜', int(150 * max(0.01, p))), W / 2 - 75 * p, 520 - 75 * p, clamp(p))
    a = ease_out(seg(t, 0.4, 1.0))
    text_center(img, X['thanks'], F('InterDisplay-Bold.otf', 78), 690 + 20 * (1 - a), WHITE, a)
    text_center(img, X['thanksb'], F('Inter-Medium.otf', 30), 800, MUTED, ease_out(seg(t, 0.7, 1.3)))
    return img

def s_credits(t, T, X):
    img = aurora(t + 14)
    a = ease_out(seg(t, 0.0, 0.5))
    text_center(img, X['credits'], F('Inter-Medium.otf', 32), 380, MUTED, a)
    for i, (name, flag) in enumerate(CREDITS):
        q = ease_out(seg(t, 0.35 + i * 0.4, 0.9 + i * 0.4))
        if q <= 0: continue
        y = 500 + i * 190 + 26 * (1 - q)
        L = layer(); d = ImageDraw.Draw(L)
        f = F('InterDisplay-Bold.otf', 58)
        line = f'{name}  •'
        tw = d.textlength(line, font=f)
        total = tw + 22 + 70
        x0 = (W - total) / 2
        rrect(d, [x0 - 36, y - 18, x0 + total + 36, y + 102], 52, fill=(255, 255, 255, int(26 * q)), outline=(212, 255, 79, int(150 * q)), width=2)
        d.text((x0, y + 4), line, font=f, fill=WHITE + (int(255 * q),))
        img.alpha_composite(L)
        paste_alpha(img, emoji_img(flag, 70), x0 + tw + 22, y + 10, q)
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

def scenes(X):
    return ([(s_open, 2.4)] + [(feature_scene(lbl, items, 3 + 4 * i), 3.0) for i, (lbl, items) in enumerate(X['scenes'])]
            + [(s_thanks, 2.2), (s_credits, 2.8), (s_end, 2.0)])

def frame_at(gt, X):
    S = scenes(X); acc = 0.0
    for i, (fn, T) in enumerate(S):
        if gt < acc + T or i == len(S) - 1:
            t = gt - acc
            img = fn(t, T, X)
            if i + 1 < len(S) and t > T - 0.25:
                nxt = S[i + 1][0](0.0, S[i + 1][1], X)
                img = Image.blend(img, nxt, ease_io((t - (T - 0.25)) / 0.25))
            return img
        acc += T

def total(X): return sum(T for _, T in scenes(X))

def render(lang, music, out):
    X = TEXT[lang]; TT = total(X)
    tmp = out + '.video.mp4'
    p = subprocess.Popen(['ffmpeg', '-y', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '30', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', tmp],
                         stdin=subprocess.PIPE)
    for i in range(int(TT * FPS)):
        p.stdin.write(frame_at(i / FPS, X).convert('RGB').tobytes())
    p.stdin.close()
    if p.wait() != 0: sys.exit('video kodlanamadı')
    af = f'afade=t=in:st=0:d=0.3,afade=t=out:st={TT - 1.6}:d=1.6'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', tmp, '-i', music, '-t', str(TT), '-map', '0:v', '-map', '1:a',
                    '-c:v', 'copy', '-af', af, '-c:a', 'aac', '-b:a', '80k', '-ac', '2', '-shortest', '-movflags', '+faststart', out], check=True)
    os.remove(tmp)

if __name__ == '__main__':
    args = sys.argv[1:]
    music = None
    if '--music' in args:
        i = args.index('--music'); music = args[i + 1]; del args[i:i + 2]
    if args and args[0] == 'stills':
        lang = args[1] if len(args) > 1 else 'tr'
        out = sys.argv[-1] if len(args) > 2 else '/tmp/claude-0/wn'
        os.makedirs(out, exist_ok=True)
        for s in (1.8, 4.6, 7.6, 10.6, 13.6, 16.6, 19.0, 21.4, 23.9):
            frame_at(s, TEXT[lang]).convert('RGB').save(f'{out}/wn_{lang}_{s:04.1f}.jpg', quality=85)
    else:
        lang = args[0] if args else 'tr'
        if not music: sys.exit('--music <wav> gerekli')
        render(lang, music, os.path.join(I.ROOT, f'assets/intro/juzzio_whatsnew_{lang}.mp4'))
