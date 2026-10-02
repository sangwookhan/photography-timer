#!/bin/bash
# fresh.sh <en|ko> [seed]: camera seed N, then remove the saved inventory so the app starts as a fresh install
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
A="adb -s emulator-5554"; P=com.sangwook.ptimer.debug
$A shell cmd locale set-app-locales $P --locales $([ $1 = en ] && echo en-US || echo ko-KR)
python3 $E/seedA.py ${2:-N} >/dev/null; sleep 2
$A shell am force-stop $P
$A shell "run-as $P rm -f files/datastore/filter_inventory.preferences_pb"
$A shell am start -n $P/com.sangwook.ptimer.MainActivity >/dev/null; sleep 3
