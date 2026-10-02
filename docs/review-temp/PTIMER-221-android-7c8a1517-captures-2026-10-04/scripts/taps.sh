#!/bin/bash
# taps.sh <lang>: header/top-row hit checks on Main (seed V). Prints what each tap opened.
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
A="adb -s emulator-5554"
state() { $E/cap.sh t_$1_$2 >/dev/null 2>&1; python3 - "$E/t_$1_$2.xml" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
t=[x for x in re.findall(r' text="([^"]+)"',s)]
sel=re.findall(r'text="(스톱|OD|ND|Stops)"[^>]*selected="true"',s)
for k in ['Shooting filters','촬영 필터','Filter management','필터 관리','Reset','초기화']:
    pass
top=' / '.join(t[:4])
print('top:',top,'| checked:',re.findall(r'checked="true"[^>]*bounds="\[(\d+),2\d\d',s)[:3])
PY
}
dp() { echo $(( $1 * 3 )); }
tap() { $A shell input tap $(dp $1) $(dp $2); sleep 1.2; }
echo "== $1"
tap 40 236; echo -n "Base Shutter caption -> "; state $1 base
tap 215 236; echo -n "ND Filter title -> "; state $1 ndt
tap 285 236; echo -n "OD option -> "; state $1 od
tap 255 236; echo -n "Stops option -> "; state $1 stops
tap 145 236; echo -n "Aux button -> "; state $1 aux
$A shell input tap 85 252; sleep 1.2
tap 200 80; echo -n "Reset -> "; state $1 reset
