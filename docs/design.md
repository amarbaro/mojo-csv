# Design

CPython 3.14 `_csv.c` supplies the licensed state-machine contract. Input is a
whole byte buffer, split into physical lines with an explicit EOL sentinel.
Raw CR/LF survive quoted fields. Reader binds input at construction; next()
advances one record and row() exposes field descriptors as spans.

Unquoted fields view input. Quoted/escaped fields append into one retained
scratch list for the row; field descriptors store offsets until all appends
finish, so scratch growth cannot invalidate earlier fields in that row.
Descriptor and scratch capacities survive next(). No per-field allocation is
needed after capacity growth, including ASCII numeric validation. Writer writes
straight into one result buffer, reserved once from the field byte sum; a 256-byte
stack table flags special bytes and fields without one are copied in bulk. to_list()/read_all() explicitly allocate copies.

All views expire on next()/reset(); input remains unchanged and outlives the
reader and views. Tested compilers accept invalid retention, so this is a caller
contract. API and SKILL document it; tests/test_lifetime.mojo verifies copies.

Runtime controls use SIMD comparisons over 16 bytes plus a scalar tail. This
supports custom byte controls without a per-dialect table or lookup gathers.
Only special bytes and state transitions take the scalar parser. Loads stay
inside input bounds; vector/tail boundaries are golden-tested.

Sizes: Dialect 40 bytes, Reader 168, CsvField view 24, OwnedField 32 (Mojo 1.2.0).
Field limit: 131072 bytes, not codepoints. Numeric syntax is ASCII; lexemes stay
bytes. Python object/file APIs are outside this contract. See oracle-coverage.md.

## Measurements

Input: 49999950 bytes, 714285 mixed records, CPU 7, compiled -O3 binary.
Three interleaved A/B rounds, same input and consumer mode for Mojo and Python.
Streaming: Mojo 227.50 MB/s versus CPython 85.79 MB/s (2.65x).
Materialized: Mojo 102.09 MB/s versus CPython 66.74 MB/s (1.53x).
Streaming peak RSS: Mojo 58504 KB, Python 303108 KB; materialized: 241324 KB
versus 562888 KB. Wall seconds in RSS runs: 0.27/0.75 and 0.54/0.97.
These are this fixture's receipts on a shared CPU, not universal speed claims.

Before Span API: owned-field reader 49.69 MB/s, 449140 KB peak. Historical
scanner steps and the reverted SIMD first-lane reduction are in
benchmarks/csv-reader.txt; final same-consumption before/after and Python
comparisons are in benchmarks/csv-reader-span.txt. Compare within each pair.
The original implementation fails on this input; its constant 100 MB/s print
was removed. Both final consumption modes meet the plan's CPython target.

Reproduce: `MOJO=path/to/mojo scripts/benchmark.sh`.
Falsifier: same-input, same-core interleaved runs at or below Python throughput,
or a golden/brute/lifetime failure. Receipts include source and binary hashes.

Final same-consumption before/after: owned API 76.96 -> 112.08 MB/s median,
0.649650 -> 0.446131 s; peak RSS 449140 -> 241324 KB. Both materialize records.

Writer (`write_all`, same 714285 records, rows materialized outside the timer):
before the byte table and reserve 242.5 MB/s with 326328 KB peak RSS, after
468.2 MB/s with 290052 KB (7 alternating rounds, CPU 7, load 3); CPython
`csv.writer` on the same rows 97.1 MB/s. Raw rounds: benchmarks/csv-writer.txt.

Measured and reverted: quoted fields as input views (no scratch copy) +0.9%
stream, 0% owned; SIMD width 32 -7%, width 8 +3% (short-field fixture). Kept 16.
