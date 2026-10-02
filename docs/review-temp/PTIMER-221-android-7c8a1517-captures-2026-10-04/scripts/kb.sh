#!/bin/bash
# kb.sh x y : bring back Gboard's docked keyboard on the field at x,y (needs show_ime_with_hard_keyboard=1)
D=emulator-5554
adb -s $D shell am force-stop com.google.android.inputmethod.latin
sleep 1
adb -s $D shell ime set com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME >/dev/null
sleep 1
adb -s $D shell input tap 400 252
sleep 0.8
adb -s $D shell input tap $1 $2
sleep 2.5
