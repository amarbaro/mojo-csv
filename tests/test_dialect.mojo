"""Dialect construction rules that the CPython vectors cannot express."""
from csv import *
from test_golden import unhex, hex_span
from std.testing import assert_equal


def one_field(d: Dialect, hex_input: String) raises -> String:
    var data = unhex(hex_input)
    var reader = Reader(d.copy(), Span(data))
    assert_equal(reader.next(), True)
    assert_equal(len(reader.row()), 1)
    return hex_span(reader.row()[0].data)


def run_dialect() raises:
    # escapechar without has_escape used to be ignored silently: a\,b split in two.
    assert_equal(one_field(Dialect(escapechar=92), "615c2c62"), "612c62")
    # NUL is a legal escape character; only has_escape=True can ask for it.
    assert_equal(one_field(Dialect(escapechar=0, has_escape=True), "61002c62"), "612c62")
    print("PASS dialect")
