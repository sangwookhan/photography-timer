# ink column runs in a horizontal band: inkruns.py png y0dp y1dp x0dp x1dp  (3 px/dp)
import sys; sys.path.insert(0,sys.path[0]); from pngrow import load
p=sys.argv[1]; y0,y1,x0,x1=[float(a) for a in sys.argv[2:6]]; S=3
w,h,bpp,rows=load(p)
bg=tuple(rows[int(y0*S)][int(x0*S)*bpp:int(x0*S)*bpp+3])
cols=[]
for x in range(int(x0*S),int(x1*S)):
    ink=any(max(abs(rows[y][x*bpp+i]-bg[i]) for i in range(3))>40 for y in range(int(y0*S),int(y1*S)))
    cols.append(ink)
runs=[];start=None
for i,c in enumerate(cols+[False]):
    if c and start is None: start=i
    if not c and start is not None:
        runs.append((start,i-1)); start=None
# merge runs with gaps < 4px (glyph spacing)
m=[]
for r in runs:
    if m and r[0]-m[-1][1]<=int(sys.argv[6]) if len(sys.argv)>6 else 12: m[-1]=(m[-1][0],r[1])
    else: m.append(r)
for a,b in m: print('ink %.1f..%.1f dp'%(x0+a/S,x0+(b+1)/S))
