#!/bin/bash
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad; A="adb -s emulator-5554"; O=$S/r7/and
bash $S/emu/tapt.sh "닫기" >/dev/null; sleep 1
$A exec-out screencap -p > $O/S05_ko_back_in_shooting_filters_after_edit.png </dev/null
bash $S/emu/tapt.sh "취소" >/dev/null; sleep 1.2
$A exec-out screencap -p > $O/S06_ko_cancel_discards_cpl_keeps_nd_holder.png </dev/null
$A shell input swipe 900 1700 200 1700 300 </dev/null; sleep 2.5
$A exec-out screencap -p > $O/A04_ko_main_zero_aux_three_standard_wheels.png </dev/null
$A shell input swipe 900 1700 200 1700 300 </dev/null; sleep 2.5
$A exec-out screencap -p > $O/A05_ko_main_zero_aux_four_standard_wheels_no_plus.png </dev/null
$A shell input swipe 200 1700 900 1700 300 </dev/null; sleep 2.5
bash $S/emu/tapt.sh "필터 선택" >/dev/null
bash $S/emu/tapt.sh "Wide Kit을\(를\) 선택한 Filter Set에 추가" >/dev/null
bash $S/emu/tapt.sh "77mm_77, CPL.*" >/dev/null
$A exec-out screencap -p > $O/S03_ko_shooting_filters_cpl_selected.png </dev/null
bash $S/emu/tapt.sh "적용" >/dev/null; sleep 2
$A exec-out screencap -p > $O/A06_ko_main_cpl_added_three_wheels_no_plus.png </dev/null
bash $S/emu/tapt.sh "필터 선택" >/dev/null
bash $S/emu/tapt.sh "Wide Kit 빼기" >/dev/null
bash $S/emu/tapt.sh "적용" >/dev/null
$A exec-out screencap -p > $O/A07_ko_main_all_removed_plus_back_at_once.png </dev/null
sleep 5; $A exec-out screencap -p > $O/A08_ko_main_all_removed_after_5s.png </dev/null
