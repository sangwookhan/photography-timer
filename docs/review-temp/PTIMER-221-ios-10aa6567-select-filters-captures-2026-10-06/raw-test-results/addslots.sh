#!/bin/bash
# addslots.sh <active slot> : add camera3 (3 Standard wheels) and camera4 (4 Standard wheels), no aux, no Sets; keeps existing slots
S=/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad
U=9144ED16-488D-41F0-B736-3E0564BC6874
D="$(xcrun simctl get_app_container $U com.sangwook.PTimer.dev data)/Library/Preferences/com.sangwook.PTimer.dev"
xcrun simctl terminate $U com.sangwook.PTimer.dev 2>/dev/null; sleep 1
H=$(python3 - "$D.plist" "$1" <<'P'
import plistlib,json,sys
d=plistlib.load(open(sys.argv[1],'rb'))
ss=json.loads(d['ptimer.camera-slot-session.snapshot'])
def slot(i,stops):
    return {"slotIDRaw":"camera%d"%i,"baseShutterSeconds":1/30,"ndStop":stops[0],
      "filterStack":[{"sourceKind":"standard","ndStop":s} for s in stops],
      "ndStack":[{"ndStop":s} for s in stops],"auxiliaryFilters":[],"candidateFilterSetIDs":[],
      "lastFilterSourceKind":"standard"}
ss['slots']=[s for s in ss['slots'] if s["slotIDRaw"] not in ("camera2","camera3","camera4")]+[slot(2,[0]),slot(3,[3,2,1]),slot(4,[3,2,1,1])]
ss['activeSlotIDRaw']=sys.argv[2]
print(json.dumps(ss).encode().hex())
P
)
xcrun simctl spawn $U defaults write "$D" ptimer.camera-slot-session.snapshot -data $H
