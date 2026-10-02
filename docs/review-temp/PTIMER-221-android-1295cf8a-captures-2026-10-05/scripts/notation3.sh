#!/bin/bash
# notation3.sh <prefix>: capture the main screen in Stops, OD, and ND notation (KO labels), then back to Stops
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
$E/tapt.sh '스톱'; $E/cap.sh r4/$1_stops >/dev/null 2>&1
$E/tapt.sh 'OD'; $E/cap.sh r4/$1_od >/dev/null 2>&1
adb -s emulator-5554 shell input tap 1000 708; sleep 1.2; $E/cap.sh r4/$1_nd >/dev/null 2>&1
$E/tapt.sh '스톱'
