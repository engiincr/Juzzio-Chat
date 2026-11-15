#!/usr/bin/env python3
"""GitHub depo görseli (Settings → Social preview, 1280x640) — kodla çizilir; yalnız Juzzio logosu
ve Inter yazı tipi (SIL OFL) kullanılır. Çıktı: docs/images/juzzio-social-preview.png
Kullanım: python3 tools/github_banner.py"""
import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont
W,H=1280,640
S=2
im=Image.new('RGB',(W*S,H*S),(3,6,15))
d=ImageDraw.Draw(im)
# vertical gradient
for y in range(H*S):
    t=y/(H*S)
    c=(int(3+10*t),int(6+14*t),int(15+40*t))
    d.line([(0,y),(W*S,y)],fill=c)
# aurora orbs
orbs=Image.new('RGB',(W*S,H*S),(0,0,0))
od=ImageDraw.Draw(orbs)
for (x,y,r,col) in [(0.12,0.1,0.55,(29,78,216)),(0.95,0.5,0.5,(14,165,233)),(0.55,1.05,0.5,(124,58,237)),(0.8,0.0,0.3,(57,123,255))]:
    R=int(r*W*S)
    od.ellipse([x*W*S-R,y*H*S-R,x*W*S+R,y*H*S+R],fill=col)
orbs=orbs.filter(ImageFilter.GaussianBlur(160*S))
im=Image.blend(im,Image.composite(orbs,im,Image.new('L',im.size,255)),0.55)
d=ImageDraw.Draw(im)
random.seed(4)
for _ in range(120):
    x=random.random()*W*S; y=random.random()*H*S; r=random.random()*1.6*S
    a=int(80+random.random()*120)
    d.ellipse([x-r,y-r,x+r,y+r],fill=(a,a,min(255,a+30)))
# glass card
card=Image.new('RGBA',im.size,(0,0,0,0))
cd=ImageDraw.Draw(card)
cx0,cy0,cx1,cy1=70*S,110*S,1210*S,530*S
cd.rounded_rectangle([cx0,cy0,cx1,cy1],radius=48*S,fill=(255,255,255,22),outline=(255,255,255,70),width=2*S)
im=Image.alpha_composite(im.convert('RGBA'),card)
# logo
logo=Image.open(os.path.join(ROOT,'assets/logo/juzzio_logo.png')).convert('RGBA').resize((250*S,250*S),Image.LANCZOS)
glow=Image.new('RGBA',im.size,(0,0,0,0))
gd=ImageDraw.Draw(glow)
gd.ellipse([135*S,185*S,135*S+270*S,185*S+270*S],fill=(80,140,255,120))
glow=glow.filter(ImageFilter.GaussianBlur(40*S))
im=Image.alpha_composite(im,glow)
im.alpha_composite(logo,(145*S,195*S))
d=ImageDraw.Draw(im)
bold=ImageFont.truetype('/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf' ,118*S) if __import__('os').path.exists('/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf') else ImageFont.truetype('/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf',118*S)
med=ImageFont.truetype('/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf',36*S)
sm=ImageFont.truetype('/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf',27*S)
x=450*S
d.text((x,190*S),'Juzzio',font=bold,fill=(242,246,255))
w=d.textlength('Juzzio',font=bold)
d.text((x+w+6*S,190*S),'.',font=bold,fill=(162,187,255))
d.text((x,335*S),'Talk to the world in your own language',font=med,fill=(214,224,248))
d.text((x,388*S),'Live-translated calls · E2EE messaging · Stories',font=sm,fill=(160,176,212))
# pills (ayrı katmanda, yarı saydam)
pl=Image.new('RGBA',im.size,(0,0,0,0))
pd=ImageDraw.Draw(pl)
px=x; py=448*S
for label in ['Live translation','E2EE','Liquid Glass']:
    tw=pd.textlength(label,font=sm)
    pd.rounded_rectangle([px,py,px+tw+36*S,py+46*S],radius=23*S,fill=(162,187,255,40),outline=(162,187,255,200),width=2*S)
    px+=tw+52*S
im=Image.alpha_composite(im,pl)
d=ImageDraw.Draw(im)
px=x
for label in ['Live translation','E2EE','Liquid Glass']:
    tw=d.textlength(label,font=sm)
    d.text((px+18*S,py+7*S),label,font=sm,fill=(236,241,255))
    px+=tw+52*S
im=im.convert('RGB').resize((W,H),Image.LANCZOS)
im.save(os.path.join(ROOT,'docs/images/juzzio-social-preview.png'),optimize=True)
print('ok')
