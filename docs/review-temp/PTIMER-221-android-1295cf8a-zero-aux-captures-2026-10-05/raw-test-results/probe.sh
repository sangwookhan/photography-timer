#!/bin/bash
# probe.sh <x dp> <name>: tap at (x, 80dp) and list what opened, then dismiss with back
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad
X=$(python3 -c "print(round($1*3))")
adb -s emulator-5554 shell input tap $X 240; sleep 1.3
bash $S/emu/cap.sh $2 >/dev/null 2>&1
cp $S/emu/$2.png $S/r6/and/$2.png
python3 $S/r6/nodes.py $S/emu/$2.xml | grep -v "Camera\|카메라\|DEBUG" | head -4
adb -s emulator-5554 shell input keyevent BACK; sleep 1
