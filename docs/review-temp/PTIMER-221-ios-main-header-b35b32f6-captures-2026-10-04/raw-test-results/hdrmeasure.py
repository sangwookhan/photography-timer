import sys
sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
p=sys.argv[1]; yh=int(sys.argv[2]); yw=int(sys.argv[3]); scale=float(sys.argv[4])
w,h,bpp,rows=load(p)
px=lambda y,x: tuple(rows[y][x*bpp:x*bpp+3])
card=px(yw,w//2)  # not used
# inner: first and last non-card pixel on wheel row, within the card (skip page bg on both sides)
row=[px(yw,x) for x in range(w)]
def near(a,b,t=4): return max(abs(a[i]-b[i]) for i in range(3))<=t
bg=row[0]
xs=[x for x in range(w) if not near(row[x],bg)]
cl,cr=xs[0],xs[-1]   # card edges
cardc=(255,255,255) if len(sys.argv)<6 else tuple(int(v) for v in sys.argv[5].split(','))
inner=[x for x in range(cl+6,cr-6) if not near(row[x],cardc,8)]
il,ir=inner[0],inner[-1]
hr=[px(yh,x) for x in range(w)]
accent=[x for x in range(cl,cr) if near(hr[x],(224,241,255),6)]
bl,br=accent[0],accent[-1]
gap=br+1
while gap<cr and not near(hr[gap],cardc,8): gap+=1
grey=[x for x in range(gap,cr-6) if not near(hr[x],cardc,8)]
tl,tr=grey[0],grey[-1]
f=lambda v: v/scale
W=ir-il
print('inner %.1f..%.1f width %.1f'%(f(il),f(ir),f(W)))
print('button %.1f..%.1f width %.1f | %.1f%%..%.1f%% (%.1f%%)'%(f(bl),f(br),f(br-bl),100*(bl-il)/W,100*(br-il)/W,100*(br-bl)/W))
print('notation %.1f..%.1f width %.1f | %.1f%%..%.1f%% (%.1f%%)'%(f(tl),f(tr),f(tr-tl),100*(tl-il)/W,100*(tr-il)/W,100*(tr-tl)/W))
