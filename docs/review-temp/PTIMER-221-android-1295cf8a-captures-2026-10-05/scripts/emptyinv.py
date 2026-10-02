# emptyinv.py: write an empty saved inventory (filterSets []) and restart the app
import subprocess,json
D='emulator-5554'; P='com.sangwook.ptimer.debug'; T='/private/tmp/claude-501/-Users-al03230922-work-playground-ptimerv1/b6d2fc20-33fa-44be-9e0d-14b722a009f8/scratchpad/emu'
def vi(n):
    out=b''
    while True:
        b=n&0x7f; n>>=7
        if n: out+=bytes([b|0x80])
        else: return out+bytes([b])
def ld(f,b): return vi((f<<3)|2)+vi(len(b))+b
def pref(key,s): return ld(1,ld(1,key.encode())+ld(2,ld(5,s.encode())))
open(T+'/fi.pb','wb').write(pref('filter_inventory_json',json.dumps({"filterSets":[],"schemaVersion":1})))
subprocess.run(['adb','-s',D,'shell','am','force-stop',P],check=True)
subprocess.run(['adb','-s',D,'push',T+'/fi.pb','/data/local/tmp/fi.pb'],check=True,capture_output=True)
subprocess.run(['adb','-s',D,'shell','run-as %s cp /data/local/tmp/fi.pb files/datastore/filter_inventory.preferences_pb; rm /data/local/tmp/fi.pb'%P],check=True)
subprocess.run(['adb','-s',D,'shell','am','start','-n',P+'/com.sangwook.ptimer.MainActivity'],check=True,capture_output=True)
