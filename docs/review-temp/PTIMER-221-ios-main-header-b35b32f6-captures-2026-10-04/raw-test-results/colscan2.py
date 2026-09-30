import sys
sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
p=sys.argv[1]; xs=[int(v) for v in sys.argv[2].split(',')]; y0,y1=int(sys.argv[3]),int(sys.argv[4])
w,h,bpp,rows=load(p)
for x in xs:
    out=[]; prev=None; start=y0
    for y in range(y0,y1):
        c=tuple(rows[y][x*bpp:x*bpp+3]); cls='W' if min(c)>=250 else 'B'
        if cls!=prev:
            if prev is not None: out.append((prev,start,y-1))
            prev=cls; start=y
    out.append((prev,start,y1-1))
    print(x,[(c,a,b) for c,a,b in out if b-a>=2])
