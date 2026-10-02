#!/bin/bash
# bprobe.sh <x dp> <name> [reset-seg-x]: optionally select a segment first, tap header at x; report sheet and selected segment (EN)
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad
if [ -n "$3" ]; then adb -s emulator-5554 shell input tap $(python3 -c "print(round($3*3))") 708 </dev/null; sleep 1; fi
X=$(python3 -c "print(round($1*3))")
adb -s emulator-5554 shell input tap $X 708 </dev/null; sleep 1.3
adb -s emulator-5554 exec-out screencap -p > $S/r8/and/$2.png </dev/null
adb -s emulator-5554 shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 </dev/null
if adb -s emulator-5554 shell cat /sdcard/ui.xml </dev/null | grep -q 'Shooting filters'; then OPEN=SHEET; else OPEN=Main; fi
python3 - $S/r8/and/$2.png $1 $OPEN <<'PY'
import sys; sys.path.insert(0,'/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad')
from pngrow import load
w,h,bpp,rows=load(sys.argv[1])
px=lambda xd,yd: tuple(rows[int(yd*3)][int(xd*3)*bpp:int(xd*3)*bpp+3])
near=lambda a,b: max(abs(a[i]-b[i]) for i in range(3))<=8
segs={'Stops':225.0,'OD':270.0,'ND':331.0}
sel=[k for k,x in segs.items() if near(px(x,226),(74,68,88))] if sys.argv[3]=='Main' else '-'
print('tap %6s dp -> %-5s selected %s'%(sys.argv[2],sys.argv[3],sel))
PY
if [ $OPEN = SHEET ]; then bash $S/emu/tapt.sh "Cancel" >/dev/null; sleep 1.5; fi
