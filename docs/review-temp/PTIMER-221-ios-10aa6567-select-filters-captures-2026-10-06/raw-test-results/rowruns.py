# rowruns.py png ypt [x0 x1]: color runs along one row (3 px/pt), runs >= 1.5 pt
import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
w,h,bpp,rows=load(sys.argv[1]); y=int(float(sys.argv[2])*3)
x0=int(float(sys.argv[3])*3) if len(sys.argv)>3 else 0; x1=int(float(sys.argv[4])*3) if len(sys.argv)>4 else w
runs=[];prev=None;start=x0
for x in range(x0,x1):
    c=tuple(rows[y][x*bpp:x*bpp+3])
    if prev is None or max(abs(a-b) for a,b in zip(c,prev))>4:
        if prev is not None: runs.append((start,x,prev))
        start=x; prev=c
runs.append((start,x1,prev))
for a,b,c in runs:
    if b-a>=5: print('%6.1f..%6.1f  %s'%(a/3,b/3,c))
