"""Field limit boundaries beyond the committed vectors. Expectations verified on CPython 3.14.8."""
from csv import *
from std.testing import assert_equal


def repeat(unit: StringSlice, count: Int) -> List[UInt8]:
    var out = List[UInt8](capacity=unit.byte_length() * count)
    for _ in range(count):
        for b in unit.as_bytes():
            out.append(b)
    return out^


def first_len(data: List[UInt8], var d: Dialect) -> Int:
    """Length of the first field, or -1 when the reader raises."""
    try:
        var reader = Reader(d^, Span(data))
        if not reader.next():
            return -2
        return len(reader.row()[0].data)
    except:
        return -1


def run_limit() raises:
    var n = FIELD_LIMIT
    assert_equal(first_len(repeat('"' + "a" * n + '"', 1), Dialect()), n)
    assert_equal(first_len(repeat('"' + "a" * (n + 1) + '"', 1), Dialect()), -1)
    assert_equal(first_len(repeat('"' + '""' * n + '"', 1), Dialect()), n)
    assert_equal(first_len(repeat('"' + '""' * (n + 1) + '"', 1), Dialect()), -1)
    assert_equal(first_len(repeat('"' + "\r\n" * (n // 2) + '"', 1), Dialect()), n)
    assert_equal(first_len(repeat('"' + "\r\n" * (n // 2) + 'a"', 1), Dialect()), -1)
    var esc = Dialect(escapechar=92, has_escape=True)
    assert_equal(first_len(repeat("\\,", n), esc.copy()), n)
    assert_equal(first_len(repeat("\\,", n + 1), esc.copy()), -1)
    assert_equal(first_len(repeat('"' + '\\"' * n + '"', 1), esc.copy()), n)
    assert_equal(first_len(repeat('"' + '\\"' * (n + 1) + '"', 1), esc.copy()), -1)
    # The limit is per field, not per record.
    assert_equal(first_len(repeat("a" * 100000 + "," + "b" * 100000, 1), Dialect()), 100000)
    print("PASS limit")
