# API

`from csv import Reader, Dialect, CsvRow, CsvField, OwnedField, write_all`.

## Dialect
`Dialect(delimiter: UInt8=44, quotechar: UInt8=34, escapechar: UInt8=0,
has_escape: Bool=False, doublequote: Bool=True, skipinitialspace: Bool=False,
strict: Bool=False, quoting: Int=QUOTE_MINIMAL)` creates a byte dialect.
A nonzero `escapechar` enables escaping by itself; `has_escape=True` is only
needed to choose NUL as the escape byte. `lineterminator: List[UInt8]` defaults to CRLF. Presets: `Dialect.excel()`,
`Dialect.excel_tab()`, `Dialect.unix_dialect()`.
`validate() raises` rejects quoting outside 0..5, CR/LF controls, quote/escape
space with skipinitialspace, collisions, and controls inside the terminator.

## Reader
`Reader(dialect, input: Span[UInt8, _])` retains a view of the caller's input.
`next() raises -> Bool` advances to a record; False means EOF.
`row() -> CsvRow` returns the current record after a successful next().
`reset()` returns to the start of input and resets line_num.
`read_all() raises -> List[List[OwnedField]]` resets, parses and copies every row.
`line_num` counts physical lines, including quoted multiline records.
The dialect is validated on first next() after construction/reset. Set it before
iteration; do not edit it during iteration. Input accepts invalid UTF-8 and NUL.
Raises on invalid dialect, strict unexpected EOF or quote suffix, fields above
131072 bytes, or invalid unquoted numeric syntax in NONNUMERIC/STRINGS modes.
Numeric modes validate ASCII float syntax and return original byte lexemes.

## Row and field views: lifetime contract
`len(row)` and `row[index] -> CsvField` expose fields, indexed from zero.
`index` must satisfy 0 <= index < len(row); release builds do not check it.
`CsvField.data: Span[UInt8]` views input for unquoted runs and retained reader
scratch for quoted/escaped content. `is_null` distinguishes None from empty bytes.
No per-field allocation occurs in iteration after buffer capacity is sufficient.

**Every row and field view is valid only until the next next() or reset().**
The input must outlive the reader and every view. Do not clear, resize, replace,
free or modify input while the reader/views are in use. Do not retain an
unquoted field merely because its bytes happen to remain in input: its row
metadata is reused too. Destruction of the reader invalidates scratch views.

**The tested compilers accept invalid retention. This is a caller contract,
not a compile-time guarantee.** `tests/lifetime/held_row.mojo` shows holding a
row across next(); it is invalid and must not be run. The same applies to
`tests/lifetime/input_lifetime.mojo`. `tests/test_lifetime.mojo` verifies owning
copies across next()/reset(), with quoted scratch overwritten by the next row.

`field.to_list() -> List[UInt8]` copies field bytes before advancement.
`row.to_list() -> List[OwnedField]` copies bytes and null flags for a whole row.
Use these helpers, or read_all(), when retaining results.

## OwnedField and writer
`OwnedField(data: List[UInt8], is_null: Bool=False)` owns its bytes;
`OwnedField()` creates an empty, non-null field. Its data remains valid until
that object is released. A null field's data is ignored by the writer.
`write_all(rows: List[List[OwnedField]], dialect: Dialect) raises -> List[UInt8]`
writes one terminator per record, including the last and empty records.
All non-null writer fields are strings: QUOTE_NONNUMERIC quotes them all.
Raises on invalid dialect, missing required escapechar, forbidden single empty
record, or unquoted empties with space delimiter plus skipinitialspace.

## Constants and limits
`QUOTE_MINIMAL=0`, `QUOTE_ALL=1`, `QUOTE_NONNUMERIC=2`, `QUOTE_NONE=3`,
`QUOTE_STRINGS=4`, `QUOTE_NOTNULL=5`, matching CPython.
STRINGS/NOTNULL preserve unquoted None versus quoted empty-string fields.
The 131072 field limit counts bytes, not Unicode codepoints. Python file/object
APIs, Sniffer, DictReader/DictWriter and non-byte dialect controls are excluded.
Error kind is checked; texts are library-specific. See oracle-coverage.md.
