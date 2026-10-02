#!/bin/bash
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad; A="adb -s emulator-5554"; O=$S/r7/and
bash $S/r6/alaunch.sh ko-KR 8
$A exec-out screencap -p > $O/A09_ko_relaunch_camera3_restored_zero_aux.png </dev/null
python3 $S/r7/addslotsA_cam2_two.py camera2 >/dev/null
bash $S/r6/alaunch.sh ko-KR 8
$A exec-out screencap -p > $O/A03_ko_main_zero_aux_two_standard_wheels.png </dev/null
python3 $S/r6/addslotsA.py camera2 >/dev/null
bash $S/r6/alaunch.sh en-US 9
$A exec-out screencap -p > $O/E01_en_main_zero_aux_standard_only.png </dev/null
bash $S/emu/cap.sh e01 >/dev/null 2>&1
python3 $S/emu/hdr2.py $S/emu/e01.xml | awk '/y  21[0-9]|y  22[0-9]|y  23[0-9]/'
