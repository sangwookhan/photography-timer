#!/usr/bin/env python3
# addslotsA.py <active>: keep the live session, set camera2 = Standard 0, camera3 = Standard 3/2/1, camera4 = Standard 3/2/1/1; no aux, no Sets
import json,subprocess,sys
D='emulator-5554'; P='com.sangwook.ptimer.debug'; T='/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/r6'
def vi(n):
    out=b''
    while True:
        b=n&0x7f; n>>=7
        if n: out+=bytes([b|0x80])
        else: return out+bytes([b])
def ld(f,b): return vi((f<<3)|2)+vi(len(b))+b
def pref(key,s): return ld(1,ld(1,key.encode())+ld(2,ld(5,s.encode())))
subprocess.run(['adb','-s',D,'shell','am','force-stop',P],check=True)
raw=subprocess.run(['adb','-s',D,'exec-out','run-as',P,'cat','files/datastore/slot_session.preferences_pb'],check=True,capture_output=True).stdout
ses=json.loads(raw[raw.find(b'{'):raw.rfind(b'}')+1])
def w(stops): return {"sourceKind":"standard","filterSetId":None,"stops":float(stops),"itemId":None,"rowKind":None,"cplLossStops":None,"gndMode":None}
def cam(stops): return {"shutterIndex":24,"ndIndex":0,"selectedFilmId":None,"selectedProfileId":None,"targetSeconds":None,"ndStops":None,
  "ndStack":[float(s) for s in stops],"filterStack":[w(s) for s in stops],"lastFilterSourceKind":"standard","lastFilterSetId":None,"auxiliaryFilters":[],"candidateFilterSetIds":[]}
ses['snapshots']['camera2']=cam([0]); ses['snapshots']['camera3']=cam([3,2,1]); ses['snapshots']['camera4']=cam([3,2,1,1])
ses['activeSlotId']=sys.argv[1]
open(T+'/ss.pb','wb').write(pref('slot_session_json',json.dumps(ses)))
subprocess.run(['adb','-s',D,'push',T+'/ss.pb','/data/local/tmp/ss.pb'],check=True,capture_output=True)
subprocess.run(['adb','-s',D,'shell','run-as %s cp /data/local/tmp/ss.pb files/datastore/slot_session.preferences_pb; rm /data/local/tmp/ss.pb'%P],check=True)
print('slots set, active',sys.argv[1])
