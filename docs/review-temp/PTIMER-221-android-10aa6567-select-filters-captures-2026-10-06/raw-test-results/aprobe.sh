#!/bin/bash
# aprobe.sh <x dp> <name>: tap the header row at x, report what opened and which notation is selected; close a sheet without key events
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad
X=$(python3 -c "print(round($1*3))")
adb -s emulator-5554 shell input tap $X 708 </dev/null; sleep 1.5
adb -s emulator-5554 exec-out screencap -p > $S/r7/and/$2.png </dev/null
adb -s emulator-5554 shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 </dev/null; adb -s emulator-5554 pull /sdcard/ui.xml $S/r7/$2.xml >/dev/null 2>&1 </dev/null
python3 - $S/r7/$2.xml <<'PY'
import re,sys
s=open(sys.argv[1]).read()
opened=('촬영 필터' in s or 'Shooting filters' in s)
sel=[re.search(r' text="([^"]*)"',n).group(1) for n in re.findall(r'<node [^>]*>',s) if 'selected="true"' in n]
sel2=[]
for m in re.finditer(r'<node [^>]*selected="true"[^>]*>(.*?)</node>',s,re.S):
    sel2+=re.findall(r' text="([^"]+)"',m.group(0))
print('opened Shooting filters' if opened else 'stayed on Main', '| selected:', [t for t in sel+sel2 if t][:3])
PY
if grep -q '촬영 필터\|Shooting filters' $S/r7/$2.xml; then bash $S/emu/tapt.sh "닫기|Close|취소|Cancel" >/dev/null; sleep 1; fi
