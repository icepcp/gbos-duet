#!/usr/bin/env python3
"""dexnatives.py file.dex...: print Lclass;->name(sig) for every native method (access & 0x100)."""
import struct, sys
def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1; r |= (x & 0x7f) << s; s += 7
        if x < 0x80: return r, o
def mutf8(b, o):
    n, o = uleb(b, o); e = b.index(b'\0', o); return b[o:e].decode('utf-8', 'replace')
for p in sys.argv[1:]:
    b = open(p, 'rb').read()
    (sid_n, sid_o, tid_n, tid_o, pid_n, pid_o, fid_n, fid_o, mid_n, mid_o, cd_n, cd_o) = struct.unpack_from('<12I', b, 56)
    S = [mutf8(b, struct.unpack_from('<I', b, sid_o + 4 * i)[0]) for i in range(sid_n)]
    T = [S[struct.unpack_from('<I', b, tid_o + 4 * i)[0]] for i in range(tid_n)]
    def proto(i):
        _, ret, par = struct.unpack_from('<III', b, pid_o + 12 * i)
        args = ''
        if par:
            n = struct.unpack_from('<I', b, par)[0]
            args = ''.join(T[struct.unpack_from('<H', b, par + 4 + 2 * k)[0]] for k in range(n))
        return '(%s)%s' % (args, T[ret])
    for c in range(cd_n):
        cls, _, _, _, _, _, cdata, _ = struct.unpack_from('<8I', b, cd_o + 32 * c)
        if not cdata: continue
        o = cdata; sf, o = uleb(b, o); inf, o = uleb(b, o); dm, o = uleb(b, o); vm, o = uleb(b, o)
        for _ in range(sf + inf): _, o = uleb(b, o); _, o = uleb(b, o)
        for n in (dm, vm):
            idx = 0
            for k in range(n):
                d, o = uleb(b, o); acc, o = uleb(b, o); _, o = uleb(b, o)
                idx = idx + d if k else d
                if acc & 0x100:
                    ccls, pr, nm = struct.unpack_from('<HHI', b, mid_o + 8 * idx)
                    print('%s->%s%s' % (T[ccls], S[nm], proto(pr)))
