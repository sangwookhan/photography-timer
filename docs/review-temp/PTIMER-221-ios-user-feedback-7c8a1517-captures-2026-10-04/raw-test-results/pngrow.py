import zlib,struct,sys
def load(p):
    d=open(p,'rb').read(); assert d[:8]==b'\x89PNG\r\n\x1a\n'
    i=8; idat=b''; w=h=ct=bd=None
    while i<len(d):
        ln=struct.unpack('>I',d[i:i+4])[0]; t=d[i+4:i+8]; c=d[i+8:i+8+ln]; i+=12+ln
        if t==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',c[:10])
        elif t==b'IDAT': idat+=c
    raw=zlib.decompress(idat); bpp={6:4,2:3}[ct]; stride=w*bpp; rows=[]; prev=bytearray(stride); o=0
    for y in range(h):
        f=raw[o]; o+=1; line=bytearray(raw[o:o+stride]); o+=stride
        for x in range(stride):
            a=line[x-bpp] if x>=bpp else 0; b=prev[x]; c2=prev[x-bpp] if x>=bpp else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+((a+b)>>1))&255
            elif f==4:
                pp=a+b-c2; pa=abs(pp-a); pb=abs(pp-b); pc=abs(pp-c2)
                line[x]=(line[x]+(a if pa<=pb and pa<=pc else (b if pb<=pc else c2)))&255
        rows.append(bytes(line)); prev=line
    return w,h,bpp,rows
def segments(p,y,tol=6):
    w,h,bpp,rows=load(p); r=rows[y]; out=[]; start=0
    px=lambda x: tuple(r[x*bpp:x*bpp+3])
    cur=px(0)
    for x in range(1,w):
        c=px(x)
        if max(abs(c[i]-cur[i]) for i in range(3))>tol:
            out.append((start,x-1,cur)); start=x; cur=c
    out.append((start,w-1,cur))
    return w,[s for s in out if s[1]-s[0]>=6]
if __name__=='__main__':
    p=sys.argv[1]; y=int(sys.argv[2])
    w,segs=segments(p,y)
    print('width',w)
    for s in segs: print(s)
