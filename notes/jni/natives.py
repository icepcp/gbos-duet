import sys,re
cls=None;name=None;typ=None
for l in sys.stdin:
    m=re.match(r"\s*Class descriptor\s*:\s*'(.+)'",l)
    if m: cls=m.group(1);continue
    m=re.match(r"\s*name\s*:\s*'(.+)'",l)
    if m: name=m.group(1);continue
    m=re.match(r"\s*type\s*:\s*'(.+)'",l)
    if m: typ=m.group(1);continue
    if re.match(r"\s*access\s*:.*NATIVE",l): print(f"{cls}->{name}{typ}")
