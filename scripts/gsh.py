#!/usr/bin/env python3
"""gsh.py 'cmd' [timeout]: run cmd as root on guest serial console, print output."""
import socket, sys, time, random, os, re
cmd = sys.argv[1]; to = float(sys.argv[2]) if len(sys.argv) > 2 else 60
m = 'MK%d' % random.randint(10**6, 10**7)
s = socket.socket(socket.AF_UNIX); s.connect(os.path.expanduser('~/gbos-duet/build/out/serial.sock'))
q = cmd.replace("'", "'\\''")
s.sendall(("\nsu 0 sh -c '%s' > /data/local/tmp/o.txt 2>&1; echo %s_$((7*6)); cat /data/local/tmp/o.txt; echo %s_END\n" % (q, m, m)).encode())
buf = b''; end = time.time() + to; s.settimeout(1)
while time.time() < end and ('\n' + m + '_END').encode() not in buf.replace(b'\r', b''):
    try: buf += s.recv(65536)
    except socket.timeout: pass
t = buf.decode('utf-8', 'replace').replace('\r', '')
a = t.find('\n' + m + '_42\n') + 1 if ('\n' + m + '_42\n') in t else -1; b = t.find('\n' + m + '_END', a)
out = t[a + len(m) + 4:b] if a >= 0 else '(timeout)\n' + t[-500:]
print('\n'.join(l for l in out.split('\n') if not re.match(r'^\[ *\d+\.\d+\]', l)))
