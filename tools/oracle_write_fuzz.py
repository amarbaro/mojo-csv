"""W differential: random rows (None, empty, specials) x dialects x quoting modes x terminators
against CPython csv.writer. Expected output is hex of the bytes, or ERR on csv.Error.
usage: oracle_write_fuzz.py OUT_PREFIX SEED COUNT -> OUT_PREFIX.bin, OUT_PREFIX.exp
"""
import csv, io, random, struct, sys
sys.stdout.reconfigure(line_buffering=True)
rnd = random.Random(int(sys.argv[2])); n = int(sys.argv[3])
alpha = b'ab,;"\'\\ \r\n\x00\xc3\xa9\t|!'
cases, exp = bytearray(), []
for _ in range(n):
    d = rnd.choice(b',;\t |'); q = rnd.choice(b'"\'"'); esc = rnd.choice([0, 92, 0x27, 124]); dq = rnd.random() < .7
    sk = rnd.random() < .3; qu = rnd.randrange(6)
    term = bytes(rnd.choice(b'\r\n!;') for _ in range(rnd.choice([0, 1, 1, 2, 2]))) if rnd.random() < .5 else b'\r\n'
    rows = []
    for _ in range(rnd.randrange(0, 4)):
        row = []
        for _ in range(rnd.choice([0, 1, 1, 2, 3])):
            row.append(None if rnd.random() < .2 else bytes(rnd.choice(alpha) for _ in range(rnd.choice([0, 0, 1, 2, 5, 20]))))
        rows.append(row)
    cases += struct.pack('<8B', d, q, esc, 1 if esc else 0, dq, sk, qu, len(term)) + term + struct.pack('<H', len(rows))
    for row in rows:
        cases += struct.pack('<B', len(row))
        for f in row:
            cases += (b'\x00' + struct.pack('<H', 0)) if f is None else (b'\x01' + struct.pack('<H', len(f)) + f)
    try:
        out = io.StringIO(newline='')
        w = csv.writer(out, delimiter=chr(d), quotechar=chr(q), escapechar=chr(esc) if esc else None, doublequote=dq,
                       skipinitialspace=sk, quoting=qu, lineterminator=term.decode('latin-1'))
        for row in rows:
            w.writerow([None if f is None else f.decode('latin-1') for f in row])
        exp.append(out.getvalue().encode('latin-1').hex())
    except (csv.Error, ValueError, TypeError):
        exp.append('ERR')
open(sys.argv[1] + '.bin', 'wb').write(cases)
open(sys.argv[1] + '.exp', 'w').write('\n'.join(exp) + '\n')
