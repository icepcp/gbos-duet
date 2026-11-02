#!/usr/bin/env python3
"""cpio_list.py <raw cpio stream> [extract_dir]: list (and extract) all concatenated newc archives"""
import sys, os
d = open(sys.argv[1], 'rb').read(); out = sys.argv[2] if len(sys.argv) > 2 else None
i = 0; arch = 0
while i < len(d):
    if d[i:i+6] != b'070701':
        i += 1; continue
    h = d[i:i+110]; f = [int(h[6+8*k:14+8*k], 16) for k in range(13)]
    mode, fsize, nsize = f[1], f[6], f[11]
    name = d[i+110:i+110+nsize-1].decode(); i = (i + 110 + nsize + 3) & ~3
    data = d[i:i+fsize]; i = (i + fsize + 3) & ~3
    if name == 'TRAILER!!!': arch += 1; continue
    print(arch, oct(mode), fsize, name)
    if out:
        p = os.path.join(out, name)
        t = mode & 0o170000
        if t == 0o040000: os.makedirs(p, exist_ok=True)
        elif t == 0o100000:
            os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'wb').write(data); os.chmod(p, mode & 0o777)
        elif t == 0o120000:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            if os.path.lexists(p): os.remove(p)
            os.symlink(data.decode(), p)
