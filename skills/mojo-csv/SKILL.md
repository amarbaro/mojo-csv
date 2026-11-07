---
name: mojo-csv
description: Read CSV byte buffers as row views and write owned CSV fields
metadata:
  short-description: CSV views, lifetime rules and owning copies
---

# mojo-csv

## When to use
Read complete CSV byte buffers row by row, or render owned fields.
Not for Python file objects, sniffing, dictionaries or streaming input chunks.

## Install
From a clone, pass `-I src` to Mojo 1.2.0. Nightly is checked too.
Example: `scripts/cap.sh mojo run -I src examples/quickstart.mojo`.

## Main calls
- `Reader(Dialect.excel(), Span(input))`: input is a `List[UInt8]` or byte span.
- `reader.next()`: True means a record is available; False means EOF.
- `reader.row()`: current `CsvRow`; use `len(row)` and `row[index]`.
- `row.to_list()`: copy a record into `List[OwnedField]` before advancing.
- `write_all(rows, dialect)`: render `List[List[OwnedField]]` as CSV bytes.

`Dialect.excel_tab()` selects tabs; `Dialect.unix_dialect()` quotes all with LF.
`reader.read_all()` resets and materializes owning rows. `reset()` restarts.

## Gotchas: lifetime is a caller contract
**Row and field views expire at the next next() or reset().** Input must outlive
the reader and its views. Keep input unchanged; do not clear, resize or free it.
Unquoted `CsvField.data` is an input Span. Quoted/escaped fields share retained
reader scratch. Both metadata and scratch are reused when advancing rows.
Do not keep a row/field view across advancement, even if compilation succeeds.
The tested compilers accept that invalid use. The example in
`tests/lifetime/held_row.mojo` is invalid and must not be run.
Use `field.to_list()` to keep bytes, `row.to_list()` to keep fields and null
flags, or `read_all()` to keep all records. Copy before next()/reset().

`OwnedField(data, is_null=False)` owns bytes; `OwnedField()` is empty non-null.
STRINGS/NOTNULL distinguish unquoted None from quoted empty bytes.
Numeric read modes validate ASCII float syntax but return original bytes.
All non-null writer fields are strings; NONNUMERIC quotes them all.
The field limit is 131072 bytes. Controls are bytes, not Unicode characters.
A nonzero escapechar enables escaping; pass has_escape=True only for a NUL escape. Set dialect before iteration, not during it.
Invalid UTF-8 passes through. Errors have library-specific text.

## Gate
`MOJO=path/to/mojo scripts/ci.sh`: goldens, independent brute oracle, lifetime
copies, compiling behavior mutants, API calls and quickstart.
`MOJO=path/to/nightly/mojo scripts/nightly.sh`: package and consumer checks.
`python3 -I tools/gen_vectors.py`: regenerate with CPython 3.14.
See docs/api.md and docs/oracle-coverage.md for contracts and exclusions.
