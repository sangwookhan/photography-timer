import re,sys
s=open('/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu/ui.xml').read()
nodes=[]
for m in re.finditer(r'<node [^>]*>',s):
    n=m.group(0)
    t=re.search(r' text="([^"]*)"',n).group(1); d=re.search(r'content-desc="([^"]*)"',n).group(1)
    b=list(map(int,re.findall(r'\d+',re.search(r'bounds="([^"]+)"',n).group(1))))
    nodes.append((t,d,b,'clickable="true"' in n))
S=3.0
# header row y range 636..780
hdr=[x for x in nodes if 630<=x[2][1]<=700 and x[2][3]<=790]
title=[x for x in hdr if x[0] in ('ND 필터 / 보조 필터','ND / Auxiliary Filters')][0]
btn=[x for x in hdr if x[3] and x[2][0]<=title[2][0] and x[2][2]>=title[2][2]][0]
opts=[x for x in hdr if x[3] and x[2][0]>btn[2][2]]
tl=min(o[2][0] for o in opts); tr=max(o[2][2] for o in opts)
cap=[x for x in hdr if x[0] in ('기본 셔터','Base Shutter')][0]
il=cap[2][0]; ir=tr; W=ir-il
f=lambda v: v/S
print('inner %.1f..%.1f dp (%.1f)'%(f(il),f(ir),f(W)))
print('caption %.1f..%.1f dp'%(f(cap[2][0]),f(cap[2][2])))
print('button %.1f..%.1f dp (%.1f) %.1f%%..%.1f%%'%(f(btn[2][0]),f(btn[2][2]),f(btn[2][2]-btn[2][0]),100*(btn[2][0]-il)/W,100*(btn[2][2]-il)/W))
print('notation %.1f..%.1f dp (%.1f, %.1f%%) %.1f%%..%.1f%%; options %s dp'%(f(tl),f(tr),f(tr-tl),100*(tr-tl)/W,100*(tl-il)/W,100*(tr-il)/W,[round(f(o[2][2]-o[2][0]),1) for o in opts]))
cols=[x for x in nodes if x[2][1]>=800 and x[2][3]<=1200 and (x[1].startswith(('기본 셔터','Base Shutter','필터 ','Filter ','보조 필터','Auxiliary filters')) )]
for c in cols: print('  column %-30s y %.1f..%.1f dp x %.1f..%.1f'%(c[1][:30],f(c[2][1]),f(c[2][3]),f(c[2][0]),f(c[2][2])))
