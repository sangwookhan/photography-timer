import re,sys
s=open(sys.argv[1]).read()
for m in re.finditer(r'<node [^>]*>',s):
    n=m.group(0)
    t=re.search(r' text="([^"]*)"',n).group(1); d=re.search(r'content-desc="([^"]*)"',n).group(1)
    b=list(map(int,re.findall(r'\d+',re.search(r'bounds="([^"]+)"',n).group(1))))
    c='clickable="true"' in n
    if b[3]<=800 and b[1]>=150 and (t or d or c):
        print('%-5s %-28s %-22s x %6.1f..%6.1f  y %6.1f..%6.1f dp'%('CLICK' if c else '', (t or '')[:28], (d or '')[:22], b[0]/3,b[2]/3,b[1]/3,b[3]/3))
