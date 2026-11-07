# CPython oracle coverage

Source: CPython v3.14.0 `Modules/_csv.c`; generator runs CPython 3.14.
`tools/gen_vectors.py` writes the committed byte/null/error vectors.
`tests/test_golden.mojo` replays each and checks reader reuse. `!` means an
exception, with library-specific text. Numeric values retain their input lexeme;
CPython validates conversion before the oracle records that lexeme.

| CPython branch or rejection | Named golden rows |
|---|---|
| START_RECORD empty/EOL/CR/LF/ordinary | empty, blank-*, plain-lines, iterator-empty |
| START_FIELD quote/escape/space/delimiter/ordinary/EOL | quoted-empty, escape-*, skip-spaces, empty-fields, plain-eof, trailing-* |
| ESCAPED_CHAR CR/LF/EOL/ordinary | escape-4-*, escape-5-*, escape-6-*, escaped-eol, escape-2-* |
| AFTER_ESCAPED_CRNL EOL/fallthrough | escape-4-*, escape-5-*, escape-6-*, random-279 |
| IN_FIELD CR/LF/EOL/escape/delimiter/ordinary | plain-lines, iterator-eol, escape-3-*, plain-eof |
| IN_QUOTED_FIELD EOL/escape/quote/ordinary | quoted-eol, quoted-multiline, quoted-escape-eol, doubled-quote, no-double |
| ESCAPE_IN_QUOTED_FIELD EOL/CR/LF/ordinary | quoted-escape-eol, escape-8-*, escape-9-*, escape-7-* |
| QUOTE_IN_QUOTED_FIELD quote/delimiter/EOL/CR/LF/suffix | doubled-quote, quote-delimiter, quote-eof, quote-cr, quoted-comma, quote-suffix |
| Strict suffix rejection | strict-226122780a |
| EAT_CRNL CR/LF/EOL/bad byte | eat-crnl-ignore, plain-lines, eat-crnl-error |
| EOF strict/open quote/escape/trailing field | strict-22616263, open-quote, escape-0-*, escape-10-*, trailing-eof |
| Field limit exact/overflow | limit-exact, limit-over |
| All quoting modes reader/writer | mode-0..5, writer-0..5-* |
| NOTNULL/STRINGS None versus empty quoted bytes | mode-4, mode-5, empty-null-4, writer-4-4, writer-5-4 |
| Numeric conversion success/failure | float-2-*, float-4-*, quoted-nonnumeric-* |
| Writer escape required, quote doubling/disabled | writer-3-6, writer-escape-*, writer-no-escape-quote |
| Writer single empty record/None rejection | writer-0..5-2, writer-0..5-3 |
| Writer space delimiter + skipinitialspace empty rejection | writer-space-* |
| Writer terminator characters and final terminator | writer-custom-term, writer-0-5 |
| Invalid quoting range | invalid-quoting-* |
| Invalid dialect CR/LF/space | invalid-delimiter-*, invalid-quotechar-*, invalid-escapechar-*, *space-rejected |
| Dialect character inside terminator | term-collision-* |
| Pairwise character collisions | delimiter-quote-collision, delimiter-escape-collision, quote-escape-collision |
| Space allowed when skipinitialspace is false | quote-space-allowed, escape-space-allowed |
| Invalid UTF-8 bytes preserved | invalid-continuation, invalid-truncated, writer-0..5-7 |
| Null byte, valid UTF-8 | nul, utf8 |
| Random combinations | random-0..999 |

The `L` vectors use the actual internal transition function with explicit
iterator EOL markers, matching CPython's iterable-of-lines interface. This is
needed to reach EAT_CRNL's bad-byte raise: the public byte-buffer reader splits
physical lines itself, so that bad iterable element cannot be supplied there.

CPython-only raises are outside this typed API: registry lookup, iterator and
writer-object/type validation, missing/invalid keyword types, missing quotechar,
string length/type checks, user object conversion failures, allocation failure,
field-limit setter and size overflow. Byte controls cannot express multi-codepoint
or non-byte delimiters. These are interface exclusions, not covered raises.
The 131072 field limit counts bytes, rather than Unicode codepoints. Numeric
validation supports ASCII float syntax. These byte-API differences are explicit.

SIMD boundaries: simd-plain/quote/escaped/quoted-escape at payload lengths
0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65 exercise vector and scalar tails.

The R vectors replay both next()/row() views and read_all() owning copies.
Lifetime checks cover direct input pointers, retained scratch capacity and
copies surviving next/reset. Invalid-retention examples are documented caller
contract violations; successful compilation is not counted as a lifetime gate.

Beyond the vectors: tests/test_limit.mojo pins the 131072 boundary for quoted,
doubled-quote, escaped and CRLF fields (CPython 3.14.8 results). tests/test_dialect.mojo
pins escapechar inference. ci.sh runs 20000 random reader cases (five delimiters,
two quote bytes, four escape bytes, six quoting modes, numeric-heavy and 300-byte
inputs, `line_num` per row) and 20000 random writer cases (None, empty, special
fields, five terminators) against CPython; a corrupted expectation must fail.

