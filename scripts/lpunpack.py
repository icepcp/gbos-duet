#!/usr/bin/env python3
"""Minimal lpunpack: lpunpack.py <disk.raw> <super_byte_offset> <outdir> [names...]"""
import struct, sys, os
disk, base, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]; want = sys.argv[4:]
os.makedirs(out, exist_ok=True)
f = open(disk, 'rb')
f.seek(base + 4096); g = f.read(52)
assert struct.unpack_from('<I', g, 0)[0] == 0x616c4467, 'bad geometry'
f.seek(base + 4096 * 3); h = f.read(256)
assert struct.unpack_from('<I', h, 0)[0] == 0x414C5030, 'bad header'
hsize = struct.unpack_from('<I', h, 8)[0]
tsize = struct.unpack_from('<I', h, 44)[0]
P = struct.unpack_from('<III', h, 80); E = struct.unpack_from('<III', h, 92)
f.seek(base + 4096 * 3 + hsize); t = f.read(tsize)
exts = [struct.unpack_from('<QIQI', t, E[0] + i * E[2]) for i in range(E[1])]
for i in range(P[1]):
    e = t[P[0] + i * P[2]: P[0] + (i + 1) * P[2]]
    name = e[:36].split(b'\0')[0].decode(); attr, first, n, grp = struct.unpack_from('<IIII', e, 36)
    size = sum(exts[first + j][0] for j in range(n)) * 512
    print(f'{name:24} {size/2**20:10.1f} MiB  extents={n}')
    if not size or (want and name not in want): continue
    with open(f'{out}/{name}.img', 'wb') as o:
        for j in range(n):
            ns, tt, data, src = exts[first + j]
            if tt == 0:
                f.seek(base + data * 512); left = ns * 512
                while left:
                    b = f.read(min(left, 64 << 20)); o.write(b); left -= len(b)
            else: o.seek(ns * 512, 1)
        o.truncate()
