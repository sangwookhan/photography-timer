#!/bin/bash
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad; A="adb -s emulator-5554"
$A shell input tap 900 624 </dev/null; sleep 0.8
$A shell input keyevent KEYCODE_MOVE_END </dev/null
$A shell input text "_77" </dev/null; sleep 0.8
$A exec-out screencap -p > $S/r7/and/S04_ko_edit_filter_from_shooting_filters.png </dev/null
bash $S/emu/tapt.sh "저장" >/dev/null; sleep 1.2
$A exec-out screencap -p > $S/r7/and/S04b_ko_set_editor_after_save.png </dev/null
