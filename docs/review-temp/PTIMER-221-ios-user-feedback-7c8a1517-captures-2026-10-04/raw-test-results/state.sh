#!/bin/bash
# state.sh <name>: screenshot and classify what the last tap opened (none / RESET-DIALOG / MENU / SHEET)
SP=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad
sleep 1.2; xcrun simctl io 9144ED16-488D-41F0-B736-3E0564BC6874 screenshot $SP/ios7c/$1.png >/dev/null 2>&1
python3 - $SP/ios7c/$1.png <<'PY'
import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
w,h,bpp,rows=load(sys.argv[1])
def px(x,y): r=rows[int(y*3)]; i=int(x*3)*bpp; return tuple(r[i:i+3])
red=lambda c: c[0]>200 and c[1]<120 and c[2]<120
if any(red(px(x,y)) for x in range(150,400,2) for y in (200,208,216,258,266)): k='RESET-DIALOG'
elif sum(px(200,40))<680: k='SHEET'
elif px(300,166)!=px(60,166): k='MENU'
else: k='none'
print(sys.argv[1].split('/')[-1], k)
PY
