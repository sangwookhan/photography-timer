import sys
sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
p=sys.argv[1]; y0,y1=int(sys.argv[2]),int(sys.argv[3]); scale=float(sys.argv[4]); thr=int(sys.argv[5]) if len(sys.argv)>5 else 120
w,h,bpp,rows=load(p)
cols=[any(max(rows[y][x*bpp:x*bpp+3])<thr for y in range(y0,y1)) for x in range(w)]
runs=[];start=None
for x,c in enumerate(cols+[False]):
    if c and start is None: start=x
    if not c and start is not None:
        runs.append((start,x-1)); start=None
# merge runs separated by < 12px (letter gaps)
merged=[]
for r in runs:
    if merged and r[0]-merged[-1][1]<=18: merged[-1]=(merged[-1][0],r[1])
    else: merged.append(r)
for a,b in merged: print('dark %.1f..%.1f pt'%(a/scale,b/scale))
