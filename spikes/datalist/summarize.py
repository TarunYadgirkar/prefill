import sys,re
for p in sys.argv[1:]:
    t=open(p).read().split('\n')
    bar=[];dd=[];acc=[]
    inbar=False
    for i,l in enumerate(t):
        if "label: 'Typing Predictions'" in l: inbar=True; continue
        m=re.search(r"Button, 0x\w+, \{\{([\d.]+), ([\d.]+)\}.*label: '(.*)", l)
        if m:
            lab=m.group(3)
            if not lab.endswith("'") and i+1<len(t): lab+=' / '+t[i+1].rstrip("'")
            lab=lab.rstrip("'")
            if inbar and float(m.group(2))>=500: bar.append(lab)
            elif re.search(r'@example|Label \d|pg-|mut-',lab) : dd.append(lab)
            elif lab in ('AutoFill Contact','Done','Previous','Next') or 'AutoFill' in lab: acc.append(lab)
        if inbar and re.search(r"Other, 0x\w+, \{\{0.0, [\d.]+\}, \{402.0, 3\d\d",l): inbar=False
    print(p.split('/')[-1]); print('  bar:',bar); print('  dropdown/other:',dd); print('  accessory:',acc)
