"""R differential: random bytes x random dialects x all six quoting modes against CPython csv.reader.

Latin-1 maps one byte to one char. Numeric modes compare the raw lexeme CPython converted.
Each expected row carries reader.line_num so line counting is checked too.
usage: oracle_fuzz.py OUT_PREFIX SEED COUNT  ->  OUT_PREFIX.bin (cases), OUT_PREFIX.exp (expected)
"""
import csv, io, random, struct, sys
sys.stdout.reconfigure(line_buffering=True)
rnd = random.Random(int(sys.argv[2])); n = int(sys.argv[3])
STRUCT = b'ab,;"\'\\ \r\n\x00\xc3\xa9\t|'
NUMERIC = b'0123456789.e-+_inf nNaA,"\r\n\t\x0b\x0c\x1c\x1d\x1e\x1f'
cases, exp = bytearray(), []
for _ in range(n):
    d = rnd.choice(b',;\t |'); q = rnd.choice(b'"\'"'); esc = rnd.choice([0, 92, 0x27, 124])
    dq = rnd.random() < .7; sk = rnd.random() < .3; st = rnd.random() < .3; qu = rnd.randrange(6)
    alpha = rnd.choice([STRUCT, NUMERIC]) + b'abcdefghij' * rnd.choice([0, 0, 5, 30])
    data = bytes(rnd.choice(alpha) for _ in range(rnd.choice([rnd.randrange(30), rnd.randrange(300)])))
    cases += struct.pack('<8BI', d, q, esc, 1 if esc else 0, dq, sk, st, qu, len(data)) + data
    kw = dict(delimiter=chr(d), quotechar=chr(q), escapechar=chr(esc) if esc else None, doublequote=dq,
              skipinitialspace=sk, strict=st, quoting=qu)
    try:
        text = data.decode('latin-1')
        rd = csv.reader(io.StringIO(text, newline=''), **kw)
        rows, lines = [], []
        for row in rd:
            rows.append(row); lines.append(rd.line_num)
        if qu in (2, 4):
            lex = list(csv.reader(io.StringIO(text, newline=''), **dict(kw, quoting=0)))
            rows = [[raw if isinstance(f, float) else f for f, raw in zip(r, l)] for r, l in zip(rows, lex)]
        exp.append('|'.join(str(ln) + ':' + ','.join('N' if f is None else 'h' + f.encode('latin-1').hex() for f in row)
                            for ln, row in zip(lines, rows)))
    except (csv.Error, ValueError, TypeError):
        exp.append('ERR')
open(sys.argv[1] + '.bin', 'wb').write(cases)
open(sys.argv[1] + '.exp', 'w').write('\n'.join(exp) + '\n')
