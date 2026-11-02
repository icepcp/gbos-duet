#!/usr/bin/env python3
"""Minimal lpmake (LP metadata v10.0, 1 slot, no slot suffixes).
lpmake.py OUT.img name=path.img [name=path.img ...]   -> raw super image sized to fit (+64MiB)"""
import hashlib, struct, sys, os
MAXMETA, SLOTS, BS, ALIGN = 65536, 1, 4096, 1 << 20
parts = [a.split('=', 1) for a in sys.argv[2:]]
first = ALIGN  # bytes; data starts at 1MiB (metadata region: 4K+2*4K+2*64K < 1MiB)
exts, pents, off = [], [], first
for i, (n, p) in enumerate(parts):
    sz = (os.path.getsize(p) + BS - 1) // BS * BS
    exts.append(struct.pack('<QIQI', sz // 512, 0, off // 512, 0))
    pents.append(n.encode().ljust(36, b'\0') + struct.pack('<IIII', 1, i, 1, 0))
    off = (off + sz + ALIGN - 1) // ALIGN * ALIGN
total = off + (64 << 20)
groups = [b'default'.ljust(36, b'\0') + struct.pack('<IQ', 0, 0)]
bdev = [struct.pack('<QIIQ', first // 512, 0, 0, total) + b'super'.ljust(36, b'\0') + struct.pack('<I', 0)]
P, E, G, B = b''.join(pents), b''.join(exts), b''.join(groups), b''.join(bdev)
tables = P + E + G + B
def hdr(cksum):
    return struct.pack('<IHHI', 0x414C5030, 10, 0, 128) + cksum + struct.pack('<I', len(tables)) + \
        hashlib.sha256(tables).digest() + struct.pack('<9I', 0, len(pents), 52, len(P), len(exts), 24,
        len(P) + len(E), len(groups), 48) + struct.pack('<3I', len(P) + len(E) + len(G), len(bdev), 64)
h = hdr(bytes(32)); assert len(h) == 128; h = hdr(hashlib.sha256(h).digest())
meta = (h + tables).ljust(MAXMETA, b'\0')
g = struct.pack('<II', 0x616c4467, 52) + bytes(32) + struct.pack('<III', MAXMETA, SLOTS, BS)
g = g[:8] + hashlib.sha256(g).digest() + g[40:]; g = g.ljust(4096, b'\0')
with open(sys.argv[1], 'wb') as o:
    o.truncate(total)
    o.seek(4096); o.write(g); o.write(g)
    o.write(meta * SLOTS); o.write(meta * SLOTS)
    for (n, p), e in zip(parts, exts):
        o.seek(struct.unpack_from('<QIQI', e)[2] * 512)
        with open(p, 'rb') as f:
            while (b := f.read(64 << 20)): o.write(b)
print('super', total >> 20, 'MiB')
