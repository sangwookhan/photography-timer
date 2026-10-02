#!/bin/bash
# nav_new.sh <en|ko> <setname>: seed A, open Settings > Filter management > set > Add filter
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
A="adb -s emulator-5554"
loc=$([ $1 = en ] && echo en-US || echo ko-KR)
$A shell cmd locale set-app-locales com.sangwook.ptimer.debug --locales $loc
python3 $E/seedA.py A >/dev/null; sleep 3
$E/tapt.sh 'Settings|설정' && $E/tapt.sh 'Filter management|필터 관리' && $E/tapt.sh "$2" || exit 1
$A shell input swipe 540 2000 540 500 300; sleep 1
$E/tapt.sh 'Add filter|필터 추가'
