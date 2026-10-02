#!/bin/bash
# edcap.sh <lang> : per kind, keyboard-closed + docked-keyboard captures of the item editor.
# Avoid key events (they switch Gboard to its hardware-keyboard toolbar for ~45 s);
# hide by stopping Gboard, show with kb.sh; each capture is checked and retried.
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
A="adb -s emulator-5554"
kb() { python3 -c "
import sys; sys.path.insert(0,'$E/..'); from pngrow import load
w,h,bpp,rows=load('$E/$1.png'); print('open' if rows[1700][300]>200 else 'closed')"; }
kx=(181 344 540 735 931); kn=(nd color effect cpl gnd)
for i in 0 1 2 3 4; do
  n=ed_${kn[$i]}_$1_closed
  for t in 1 2 3 4; do
    $A shell am force-stop com.google.android.inputmethod.latin; sleep 2
    [ $t = 1 ] && { $A shell input tap ${kx[$i]} 826; sleep 1.2; }
    $E/cap.sh $n >/dev/null 2>&1; [ "$(kb $n)" = closed ] && break
  done
  echo "$n $(kb $n) tries=$t"
  n=ed_${kn[$i]}_$1_kb
  for t in 1 2 3 4; do
    $E/kb.sh 540 660; $E/cap.sh $n >/dev/null 2>&1; [ "$(kb $n)" = open ] && break
  done
  echo "$n $(kb $n) tries=$t"
done
