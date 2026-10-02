#!/bin/bash
# edcap2.sh <prefix> <kind regex>...: per kind, keyboard-closed and docked-keyboard captures into r2/<prefix>_<n>_{closed,open}
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
A="adb -s emulator-5554"
kb() { python3 -c "
import sys; sys.path.insert(0,'$E/..'); from pngrow import load
w,h,bpp,rows=load('$E/$1.png'); print('open' if rows[1700][300]>200 else 'closed')"; }
name=$($A shell uiautomator dump /sdcard/ui.xml >/dev/null; $A shell cat /sdcard/ui.xml | python3 -c "
import re,sys; s=sys.stdin.read(); m=re.search(r'text=\"(Filter name|필터 이름)\"',s); print('ok' if m else 'none')")
p=$1; shift; i=1
for k in "$@"; do
  $E/tapt.sh "$k" || exit 1
  n=r2/${p}_${i}_closed
  for t in 1 2 3 4 5 6; do $A shell am force-stop com.google.android.inputmethod.latin; sleep 1.5; $E/cap.sh $n >/dev/null 2>&1; [ "$(kb $n)" = closed ] && break; done
  echo "$n $(kb $n)"
  n=r2/${p}_${i}_open
  # tap the name field (first editable) to bring the docked keyboard back
  xy=$($E/tapt.sh 'XXXX' >/dev/null 2>&1; python3 - <<'PY'
import re
s=open('/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu/_t.xml').read()
for m in re.finditer(r'<node [^>]*class="android.widget.EditText"[^>]*>',s):
    b=list(map(int,re.findall(r'\d+',re.search(r'bounds="([^"]+)"',m.group(0)).group(1))))
    if b[1]>500: print((b[0]+b[2])//2,(b[1]+b[3])//2); break
PY
)
  for t in 1 2 3 4; do $E/kb.sh $xy; $E/cap.sh $n >/dev/null 2>&1; [ "$(kb $n)" = open ] && break; done
  echo "$n $(kb $n) (field $xy)"
  i=$((i+1))
done
