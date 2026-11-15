# Juzzio — özgün (telifsiz) fon müziği üreticisi. Tamamen matematiksel sentez; örnek/sample yok.
import numpy as np, sys, wave
sr = 44100
def note(f, dur, amp=0.2, attack=0.02, release=0.4, kind='pad'):
    t = np.arange(int(sr*dur))/sr
    if kind == 'pad':
        w = (np.sin(2*np.pi*f*t) + 0.5*np.sin(2*np.pi*f*2.003*t) + 0.25*np.sin(2*np.pi*f*0.5*t))
    elif kind == 'pluck':
        w = np.sin(2*np.pi*f*t) * np.exp(-t*5) + 0.3*np.sin(2*np.pi*f*3*t)*np.exp(-t*9)
    else:
        w = np.sin(2*np.pi*f*t)
    env = np.minimum(1, t/attack) * np.minimum(1, np.maximum(0, (dur - t))/release)
    return amp * w * env
def hz(m): return 440*2**((m-69)/12)
def render(length, seed, out):
    rng = np.random.default_rng(seed)
    buf = np.zeros(int(sr*(length+6)))
    # I–vi–IV–V benzeri ama kendi dizimiz: C maj7, A min9, F maj7, G sus
    prog = [[48,55,59,64],[45,52,55,60,62],[41,48,52,57],[43,50,55,60]]
    bar = 2.4
    i = 0; tpos = 0.0
    while tpos < length:
        ch = prog[i % len(prog)]
        for m in ch:
            s = note(hz(m), bar+0.6, amp=0.05, attack=0.5, release=1.0)
            a = int(sr*tpos); buf[a:a+len(s)] += s
        # arpej
        for k in range(8):
            m = ch[rng.integers(0,len(ch))] + 12*(1 + (k%2))
            s = note(hz(m), 0.5, amp=0.07, attack=0.005, release=0.35, kind='pluck')
            a = int(sr*(tpos + k*bar/8)); buf[a:a+len(s)] += s
        # bas
        s = note(hz(ch[0]-12), bar, amp=0.12, attack=0.03, release=0.5, kind='sine')
        a = int(sr*tpos); buf[a:a+len(s)] += s
        tpos += bar; i += 1
    buf = buf[:int(sr*length)]
    fade = int(sr*1.5)
    buf[:int(sr*0.4)] *= np.linspace(0,1,int(sr*0.4)); buf[-fade:] *= np.linspace(1,0,fade)
    # basit stereo genişlik + yankı
    d = int(sr*0.23); wet = np.zeros_like(buf); wet[d:] = buf[:-d]*0.35
    L = buf + wet; R = buf + np.roll(wet, int(sr*0.05))
    st = np.stack([L,R],1); st /= np.max(np.abs(st))*1.12
    pcm = (st*32767).astype(np.int16)
    with wave.open(out,'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())
render(float(sys.argv[1]), int(sys.argv[2]), sys.argv[3])
