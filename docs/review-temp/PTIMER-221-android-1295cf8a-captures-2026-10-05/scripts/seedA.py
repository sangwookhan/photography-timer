#!/usr/bin/env python3
# Seeds emulator-5554 with the iOS #71 representative data. Variant via argv[1]: A (six mounted), B (no mounts, ND Holder wheel), T30, W4, D (Pouch only, Standard).
import json,subprocess,sys
D='emulator-5554'; P='com.sangwook.ptimer.debug'; T='/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu'
v=sys.argv[1] if len(sys.argv)>1 else 'A'
def vi(n):
    out=b''
    while True:
        b=n&0x7f; n>>=7
        if n: out+=bytes([b|0x80])
        else: return out+bytes([b])
def ld(f,b): return vi((f<<3)|2)+vi(len(b))+b
def pref(key,s): return ld(1,ld(1,key.encode())+ld(2,ld(5,s.encode())))
K,P_,N,E,W='s-72','s-pouch','s-ndh','s-empty','s-wide'
inv={"filterSets":[
 {"id":"default","name":"Default","color":"blue","items":[]},
 {"id":P_,"name":"Pouch","color":"orange","items":[{"id":"i-red","name":"Red 25A","kind":"color","value":3.0,"opticalColor":"red"},{"id":"i-hgnd","name":"Hard GND 0.9","kind":"gnd","value":0.9,"unit":"opticalDensity"}]},
 {"id":K,"name":"72mm Kit","color":"blue","items":[
   {"id":"i-nd8","name":"ND8","kind":"fixed","value":3.0,"unit":"stops"},
   {"id":"i-marumi","name":"MARUMI Red R2X1 72mm","kind":"color","value":1.0,"opticalColor":"red"},
   {"id":"i-y2","name":"Yellow Y2","kind":"color","value":1.0,"opticalColor":"yellow"},
   {"id":"i-ya3","name":"YA3","kind":"color","value":1.5,"opticalColor":"yellowOrange"},
   {"id":"i-xo","name":"XO Yellow-green","kind":"color","value":1.0,"opticalColor":"yellowGreen"},
   {"id":"i-night","name":"Night","kind":"effect","value":1.0},
   {"id":"i-72","name":"72mm","kind":"cpl","cplChoices":[1.0,1.5,2.0]},
   {"id":"i-sgnd","name":"Soft GND 2","kind":"gnd","value":2.0,"unit":"stops"}]},
 {"id":N,"name":"ND Holder","color":"teal","items":[{"id":"i-h8","name":"ND8","kind":"fixed","value":3.0,"unit":"stops"},{"id":"i-h1000","name":"ND1000","kind":"fixed","value":1000.0,"unit":"filterFactor"}]},
 {"id":E,"name":"Empty Holder","color":"green","items":[]},
 {"id":W,"name":"Wide Kit","color":"purple","items":[{"id":"i-77","name":"77mm","kind":"cpl","cplChoices":[1.0,1.5,2.0]}]}],"schemaVersion":1}
def w(src,stops=None,setid=None,item=None,kind=None): return {"sourceKind":src,"filterSetId":setid,"stops":stops,"itemId":item,"rowKind":kind,"cplLossStops":None,"gndMode":None}
def a(s,i,k,g=None,c=None): return {"filterSetId":s,"itemId":i,"kind":k,"cplLossStops":c,"gndMode":g}
mounts=[a(K,"i-marumi","color"),a(K,"i-night","effect"),a(K,"i-72","cpl",c=1.5),a(K,"i-sgnd","gnd","recordOnly"),a(P_,"i-red","color"),a(P_,"i-hgnd","gnd","applyFullValue")]
stack=[w("filterSet",setid=K,item="i-nd8",kind="fixed"),w("standard",stops=2.0)]
cands=[K,P_,N]
if v=='B': mounts=[]
if v=='T30': stack=[w("filterSet",setid=K,item="i-nd8",kind="fixed"),w("standard",stops=17.0)]
if v=='W4': mounts=[]; stack=[w("filterSet",setid=K,item="i-nd8",kind="fixed"),w("standard",stops=2.0),w("filterSet",setid=N,item="i-h8",kind="fixed"),w("standard",stops=1.0)]
if v=='D': mounts=[]; stack=[w("standard",stops=2.0)]; cands=[P_]
if v=='V': mounts=[]; stack=[w('standard',stops=2.0),w('filterSet',setid=N,item='i-h8',kind='fixed')]; cands=[N,P_]
if v=='C': mounts=[]; cands=[P_,"default",K,W,N,E]
if v=='S': stack=[w('filterSet',setid=K,item='i-nd8',kind='fixed'),w('filterSet',setid=N,item='i-h1000',kind='fixed')]
if v=='H': stack=[w('filterSet',setid=K,item='i-nd8',kind='fixed'),w('filterSet',setid=N,item='i-h8',kind='fixed'),w('filterSet',setid=N,item='i-h1000',kind='fixed')]
if v=='P': stack=[w('filterSet',setid=K,item='i-nd8',kind='fixed'),w('filterSet',setid=N,item='i-h8',kind='fixed'),w('filterSet',setid=N,item='i-h1000',kind='fixed')]; mounts=[a(P_,'i-red','color'),a(P_,'i-hgnd','gnd','applyFullValue')]
if v=='Q': stack=[w('filterSet',setid=K,item='i-nd8',kind='fixed'),w('filterSet',setid=N,item='i-h8',kind='fixed'),w('filterSet',setid=N,item='i-h1000',kind='fixed')]; mounts=[]
if v.startswith('M'): mounts=mounts[:int(v[1:])]
if v=='N': mounts=[]; stack=[w('standard',stops=2.0)]; cands=[]
if v=='Z': mounts=[]; stack=[w('standard',stops=0.0)]; cands=[P_]
cam={"shutterIndex":24,"ndIndex":2,"selectedFilmId":None,"selectedProfileId":None,"targetSeconds":None,"ndStops":None,"ndStack":[2.0],
 "filterStack":stack,"lastFilterSourceKind":"filterSet" if v not in ('D','N','Z') else "standard","lastFilterSetId":(N if v=='V' else K) if v not in ('D','N','Z') else None,
 "auxiliaryFilters":mounts,"candidateFilterSetIds":cands}
ses={"activeSlotId":"camera1","snapshots":{"camera1":cam},"customNames":{},"schemaVersion":1}
open(T+'/fi.pb','wb').write(pref('filter_inventory_json',json.dumps(inv)))
open(T+'/ss.pb','wb').write(pref('slot_session_json',json.dumps(ses)))
subprocess.run(['adb','-s',D,'shell','am','force-stop',P],check=True)
for f in ['fi','ss']: subprocess.run(['adb','-s',D,'push',T+'/'+f+'.pb','/data/local/tmp/'+f+'.pb'],check=True,capture_output=True)
subprocess.run(['adb','-s',D,'shell','run-as %s mkdir -p files/datastore'%P],check=True)
subprocess.run(['adb','-s',D,'shell','run-as %s cp /data/local/tmp/fi.pb files/datastore/filter_inventory.preferences_pb; run-as %s cp /data/local/tmp/ss.pb files/datastore/slot_session.preferences_pb; rm /data/local/tmp/fi.pb /data/local/tmp/ss.pb'%(P,P)],check=True)
subprocess.run(['adb','-s',D,'shell','am','start','-n',P+'/com.sangwook.ptimer.MainActivity'],check=True,capture_output=True)
print('seeded',v)
