<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-csv/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-csv/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-csv)](https://github.com/amarbaro/mojo-csv/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-csv)](https://github.com/amarbaro/mojo-csv/blob/main/LICENSE) [![checks](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/amarbaro/mojo-csv/badges/checks.json)](https://github.com/amarbaro/mojo-csv/actions/workflows/ci.yml)
<!-- /badges -->

# mojo-csv

CSV reader and writer for Mojo byte buffers, with CPython 3.14 quoting rules.
Unquoted fields view the input; quoted and escaped fields use retained row
scratch. Row iteration allocates only when buffers grow. Invalid UTF-8 bytes
pass through. None and empty strings remain distinct in STRINGS/NOTNULL modes.
Numeric modes validate ASCII float syntax and return its original byte lexeme.
On 50 MB of mixed records (CPU 7, receipts in [docs/benchmarks](docs/benchmarks)) the
reader streams at 227.50 MB/s against CPython 85.79 MB/s and `write_all` runs at
468.2 MB/s against 97.1 MB/s.

Install Mojo 1.2.0, then use `-I src` from this clone:

```sh
scripts/cap.sh mojo run -I src examples/quickstart.mojo
```

The quickstart binds input to Reader, advances with next(), copies rows before
advancement, and writes CRLF CSV.

| Call | Purpose |
|---|---|
| `Reader(Dialect.excel(), Span(input))` | Bind comma CSV input |
| `reader.next()` / `reader.row()` | Advance and inspect current row views |
| `field.to_list()` / `row.to_list()` | Keep owning copies before advancement |
| `reader.read_all()` | Reset and materialize all records |
| `write_all(rows, dialect)` | Write owned fields, one terminator per record |

Row and field views expire at the next next() or reset(). Input must outlive
the reader and all views and stay unchanged. The compiler accepts invalid
retention: follow the [lifetime contract](docs/api.md) and copy results you keep.

Controls are bytes; field limit is 131072 bytes. Python file/object APIs,
Sniffer, DictReader/DictWriter and non-byte dialect controls are excluded.
Error messages are library-specific.

Tested with stable Mojo 1.2.0 and nightly recorded by scripts/nightly.sh.
Run `MOJO=path/to/mojo scripts/ci.sh` for CPython goldens, an independent Mojo
scanner, lifetime copies and compiling behavior mutants. Regenerate the committed
oracle using CPython 3.14: `python3 -I tools/gen_vectors.py`.

See [API](docs/api.md), [design and measurements](docs/design.md),
[oracle branch coverage](docs/oracle-coverage.md), and the
[mojo-libs index](https://github.com/amarbaro/mojo-libs).

License: Apache-2.0; portions from CPython Modules/_csv.c under
[PSF-2.0](LICENSE-PSF). See [NOTICE](NOTICE).
