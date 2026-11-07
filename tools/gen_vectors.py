"""CPython 3.14 _csv oracle. Rows encode bytes and None without collisions."""
import csv
import io
import pathlib
import random
import sys

sys.stdout.reconfigure(line_buffering=True)
ROOT = pathlib.Path(__file__).resolve().parents[1]


def encode(rows):
    return "/".join(
        ",".join("n" if f is None else "s" + f.hex() for f in row) if row else "~"
        for row in rows
    )


def run(op, data, opts):
    if op in ("R", "L"):
        text = data.decode("utf-8", "surrogateescape") if op == "R" else None
        source = lambda: io.StringIO(text, newline="") if op == "R" else [s.decode("utf-8", "surrogateescape") for s in data]
        rows = list(csv.reader(source(), **opts))
        # Float conversion is validated by CPython, but this byte API returns lexemes.
        if opts["quoting"] in (csv.QUOTE_NONNUMERIC, csv.QUOTE_STRINGS):
            lexical = list(csv.reader(source(), **dict(opts, quoting=0)))
            rows = [[raw if isinstance(f, float) else f for f, raw in zip(row, lex)]
                    for row, lex in zip(rows, lexical)]
        return encode([[None if f is None else f.encode("utf-8", "surrogateescape")
                        for f in row] for row in rows])
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, **opts)
    writer.writerows([[None if f is None else f.decode("utf-8", "surrogateescape")
                      for f in row] for row in data])
    return stream.getvalue().encode("utf-8", "surrogateescape").hex()


def generate():
    lines, names = [], []

    def case(name, data, op="R", **overrides):
        opts = dict(delimiter=",", quotechar='"', escapechar=None,
                    doublequote=True, skipinitialspace=False, strict=False,
                    quoting=csv.QUOTE_MINIMAL, lineterminator="\r\n")
        opts.update(overrides)
        try:
            expected = run(op, data, opts)
        except (csv.Error, ValueError, TypeError):
            expected = "!"
        inp = data.hex() if op == "R" else ",".join(s.hex() for s in data) if op == "L" else encode(data)
        char = lambda c: -1 if c is None else ord(c)
        row = [name, op, char(opts["delimiter"]), char(opts["quotechar"]),
               char(opts["escapechar"]), int(opts["doublequote"]),
               int(opts["skipinitialspace"]), int(opts["strict"]), opts["quoting"],
               opts["lineterminator"].encode().hex(), inp, expected]
        lines.append("|".join(map(str, row)))
        names.append(name)

    for name, inp in [
        ("empty", b""), ("blank-lf", b"\n"), ("blank-cr", b"\r"),
        ("blank-crlf", b"\r\n\r\n"), ("plain-eof", b"a"),
        ("plain-lines", b"a,b\nc,d\r\ne,f\r"), ("empty-fields", b",,\n"),
        ("trailing-eof", b"a,"), ("trailing-lf", b"a,\n"),
        ("quoted-empty", b'""'), ("quoted-comma", b'"a,b",c\n'),
        ("quoted-multiline", b'"a\r\nb\nc\r",d\n'),
        ("doubled-quote", b'"a""b"\n'), ("quote-eof", b'"a"'),
        ("quote-cr", b'"a"\r'), ("quote-delimiter", b'"a",b'),
        ("quote-suffix", b'"a"x,b\n'), ("quote-in-unquoted", b'a"b,c'),
        ("open-quote", b'"abc'), ("nul", b"a\0b,c\n"),
        ("utf8", "é,雪\n".encode()), ("invalid-continuation", b"\x80,\xff\n"),
        ("invalid-truncated", b'"\xe2\x82",\xf8\n'),
    ]:
        case(name, inp)
    for name, chunks in [("eat-crnl-error", [b"a\nx"]), ("eat-crnl-ignore", [b"\n\r"]),
                        ("iterator-eol", [b"a", b"b"]), ("iterator-empty", [b""]),
                        ("escaped-eol", [b"a\\", b"b"]),
                        ("quoted-escape-eol", [b'"a\\', b'b"']),
                        ("quoted-eol", [b'"a', b'b"'])]:
        case(name, chunks, op="L")
    for inp in [b"a", b"a,", b'"a"', b'"abc', b'"a"x\n']:
        case("strict-" + inp.hex(), inp, strict=True)
    for i, inp in enumerate([b"\\", b"a\\", b"\\,b", b"a\\,b,c",
                             b"a\\\nb,c\n", b"a\\\r\nb,c\n",
                             b"a\\\rb,c\n", b'"a\\"b",c',
                             b'"a\\\rb",c', b'"a\\\nb",c', b'"a\\']):
        for strict in (False, True):
            case(f"escape-{i}-{strict}", inp, escapechar="\\", strict=strict)
    case("skip-spaces", b'  a,  "b",  c, \n', skipinitialspace=True)
    case("skip-after-quote", b'"a" , b\n', skipinitialspace=True)
    case("no-double", b'"a"b,c\n', doublequote=False)
    case("tab", b'a\t"b\tc"\n', delimiter="\t")
    case("space-delimiter", b'a  b \n', delimiter=" ", skipinitialspace=True)
    case("custom-quote", b"'a,b',c\n", quotechar="'")
    for mode in range(6):
        case(f"mode-{mode}", b'12,"",,3.5\n', quoting=mode)
        case(f"mode-quote-{mode}", b'"a",b\n', quoting=mode)
    for mode in (2, 4):
        for val in (b"1e3", b" -2.5e-2 ", b"+INF", b"-Infinity", b"NaN", b"1_000.5",
                    b".5", b"5.", b"1e", b"+", b"1__2", b"1e_2", b"x"):
            case(f"float-{mode}-{val.hex()}", val + b' ,"x"\n', quoting=mode)
        case(f"quoted-nonnumeric-{mode}", b'"x"\n', quoting=mode)
        case(f"empty-null-{mode}", b',"",\n', quoting=mode)
    case("limit-exact", b"a" * 131072)
    case("limit-over", b"a" * 131073)
    for width in (0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65):
        payload = b"a" * width
        case(f"simd-plain-{width}", payload + b",z\n")
        case(f"simd-quote-{width}", b'"' + payload + b'",z\n')
        case(f"simd-escaped-{width}", payload + b"\\,z\n", escapechar="\\")
        case(f"simd-quoted-escape-{width}", b'"' + payload + b'\\"z"\n', escapechar="\\")
    for mode in range(6):
        for idx, rows in enumerate([[], [[]], [[b""]], [[None]], [[None, b""]],
                                    [[b"a", b"b"], [b"c", b"d"]],
                                    [[b"a,b", b'a"b', b"a\nb"]],
                                    [[b"\x80", b"\xe2\x82\xff"]]]):
            case(f"writer-{mode}-{idx}", rows, op="W", quoting=mode)
    for idx, rows in enumerate([[[b"\\"]], [[b'a"b']], [[b"a,b"]], [[b"a\rb\nc"]]]):
        for mode in (0, 3):
            for double in (False, True):
                case(f"writer-escape-{idx}-{mode}-{double}", rows, op="W",
                     escapechar="\\", quoting=mode, doublequote=double)
    case("writer-no-escape-quote", [[b'a"b']], op="W", doublequote=False)
    case("writer-custom-term", [[b"a!b"], [b"z"]], op="W", lineterminator="!")
    # CR and LF always force quoting, even when the terminator does not contain them.
    for term in ("\n", "\r", "!"):
        for idx, field in enumerate((b"a\rb", b"a\nb")):
            case(f"writer-eol-{term.encode().hex()}-{idx}", [[field, b"z"]], op="W", lineterminator=term)
    for mode in range(6):
        for null in (False, True):
            case(f"writer-space-{mode}-{null}", [[None if null else b"", b"x"]],
                 op="W", delimiter=" ", skipinitialspace=True, quoting=mode)
    for key, vals in (("delimiter", ["\n", "\r"]), ("quotechar", ["\n", "\r", " "]),
                      ("escapechar", ["\n", "\r", " "]), ("quoting", [-1, 6])):
        for val in vals:
            case(f"invalid-{key}-{str(val).encode().hex()}", b"a,b", **{key: val})
    for key in ("delimiter", "quotechar", "escapechar"):
        case(f"term-collision-{key}", b"a", **{key: "!", "lineterminator": "!"})
    case("delimiter-quote-collision", b"a", delimiter='"')
    case("delimiter-escape-collision", b"a", escapechar=",")
    case("quote-escape-collision", b"a", escapechar='"')
    case("quote-space-allowed", b" a ", quotechar=" ")
    case("quote-space-rejected", b"a", quotechar=" ", skipinitialspace=True)
    case("escape-space-allowed", b"a b", escapechar=" ")
    case("escape-space-rejected", b"a", escapechar=" ", skipinitialspace=True)
    # Random differential uses every mode, strictness, escaping and both quote policies.
    rng = random.Random(0xC5C1)
    alphabet = b'a01, "\\\r\n\x00\x80'
    for i in range(1000):
        data = bytes(rng.choice(alphabet) for _ in range(rng.randrange(32)))
        case(f"random-{i}", data, quoting=rng.randrange(6), strict=bool(rng.randrange(2)),
             doublequote=bool(rng.randrange(2)), skipinitialspace=bool(rng.randrange(2)),
             escapechar=rng.choice([None, "\\"]))
    path = ROOT / "tests/golden/vectors.txt"
    path.write_text("\n".join(lines) + "\n")
    print(f"CPython {sys.version.split()[0]}: {len(lines)} oracle rows -> {path}")


if __name__ == "__main__":
    generate()
