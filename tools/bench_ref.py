"""Same input and consumption mode as tests/bench.mojo."""
import csv
import io
import os
import time

record = b'alpha,beta,"gamma,delta","say ""hi""",012345678901234567890123456789\r\n'
count = int(os.environ.get("BENCH_BYTES", "50000000")) // len(record)
mode = os.environ.get("BENCH_MODE", "stream")
data = record * count
stream = io.StringIO(data.decode(), newline="")
if mode == "write":
    rows = list(csv.reader(stream))
    out = io.StringIO(newline="")
    started = time.perf_counter()
    csv.writer(out).writerows(rows)
    elapsed = time.perf_counter() - started
    assert len(out.getvalue()) == len(data) and len(rows) == count
    print(f"CPython write bytes {len(data)} rows {count}")
    print(f"rows: {count}")
    print(f"parse seconds: {elapsed:.9f}")
    print(f"parse MB/s: {len(data) / elapsed / 1e6:.9f}")
    raise SystemExit(0)
started = time.perf_counter()
if mode == "owned":
    rows = list(csv.reader(stream))
    actual = len(rows)
    assert actual == count and len(rows[0]) == 5
    assert len(rows[-1][2]) == 11 and len(rows[-1][3]) == 8
else:
    actual = 0
    for row in csv.reader(stream):
        assert len(row) == 5 and len(row[2]) == 11 and len(row[3]) == 8
        actual += 1
elapsed = time.perf_counter() - started
assert actual == count
print(f"CPython {mode} bytes {len(data)} rows {actual}")
print(f"rows: {actual}")
print(f"parse seconds: {elapsed:.9f}")
print(f"parse MB/s: {len(data) / elapsed / 1e6:.9f}")
