#!/bin/bash
# tapt.sh <regex>: tap the center of the first node whose text or content-desc matches
E=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu
adb -s emulator-5554 shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb -s emulator-5554 pull /sdcard/ui.xml $E/_t.xml >/dev/null 2>&1
xy=$(python3 - "$1" <<'PY'
import re,sys
s=open('/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu/_t.xml').read()
for m in re.finditer(r'<node [^>]*>',s):
    n=m.group(0); t=re.search(r' text="([^"]*)"',n).group(1); d=re.search(r'content-desc="([^"]*)"',n).group(1)
    if re.fullmatch(sys.argv[1],t) or re.fullmatch(sys.argv[1],d):
        b=list(map(int,re.findall(r'\d+',re.search(r'bounds="([^"]+)"',n).group(1)))); print((b[0]+b[2])//2,(b[1]+b[3])//2); break
PY
)
[ -z "$xy" ] && { echo "NOT FOUND: $1"; exit 1; }
adb -s emulator-5554 shell input tap $xy; sleep 1.3
