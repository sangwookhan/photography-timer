#!/bin/bash
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad; A="adb -s emulator-5554"; O=$S/r7/and
bash $S/emu/tapt.sh "Select Filters" >/dev/null
bash $S/emu/tapt.sh "Add ND Holder to Selected Filter Sets|.*ND Holder.*Selected.*" >/dev/null
$A exec-out screencap -p > $O/S11_en_shooting_filters_nd_only_set_selected_instruction.png </dev/null
bash $S/emu/tapt.sh "Cancel" >/dev/null; sleep 1.2
$A exec-out screencap -p > $O/S12_en_cancel_keeps_main_standard_only.png </dev/null
bash $S/emu/tapt.sh "Select Filters" >/dev/null
bash $S/emu/tapt.sh "Add ND Holder to Selected Filter Sets|.*ND Holder.*Selected.*" >/dev/null
bash $S/emu/tapt.sh "Apply" >/dev/null; sleep 2
$A exec-out screencap -p > $O/E02_en_main_zero_aux_nd_only_set_selected.png </dev/null
$A shell input swipe 900 1700 200 1700 300 </dev/null; sleep 2.5
$A exec-out screencap -p > $O/E04_en_main_zero_aux_three_standard_wheels.png </dev/null
$A shell input swipe 900 1700 200 1700 300 </dev/null; sleep 2.5
$A exec-out screencap -p > $O/E05_en_main_zero_aux_four_standard_wheels_no_plus.png </dev/null
$A shell input swipe 200 1700 900 1700 300 </dev/null; sleep 2.5
bash $S/emu/tapt.sh "Select Filters" >/dev/null
bash $S/emu/tapt.sh "Add Wide Kit to Selected Filter Sets|.*Wide Kit.*Selected.*" >/dev/null
bash $S/emu/tapt.sh "77mm_77, CPL.*" >/dev/null
$A exec-out screencap -p > $O/S13_en_shooting_filters_cpl_selected.png </dev/null
bash $S/emu/tapt.sh "Apply" >/dev/null; sleep 2
$A exec-out screencap -p > $O/E06_en_main_cpl_added_three_wheels_no_plus.png </dev/null
bash $S/emu/tapt.sh "Select Filters" >/dev/null
bash $S/emu/tapt.sh "Remove Wide Kit" >/dev/null
bash $S/emu/tapt.sh "Apply" >/dev/null
$A exec-out screencap -p > $O/E07_en_main_all_removed_plus_back_at_once.png </dev/null
python3 $S/r7/addslotsA_cam2_two.py camera2 >/dev/null
bash $S/r6/alaunch.sh en-US 8
$A exec-out screencap -p > $O/E03_en_main_zero_aux_two_standard_wheels.png </dev/null
